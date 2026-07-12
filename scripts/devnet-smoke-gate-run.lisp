(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-run
    (case-name &key ready-file log-file pid-file database-file
       state-prune-before terminal-total-difficulty
       terminal-total-difficulty-passed-p terminal-block-hash
       terminal-block-number)
  #+sbcl
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-jwt" "hex"))
        (journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-smoke-txpool-journal"
                                "sexp")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let ((report
                   (devnet-smoke-gate-call-with-telemetry-sink
                    log-file
                    (lambda (telemetry-sink)
                      (let* ((fixture
                               (devnet-smoke-gate-engine-fixture case-name))
                             (store
                               (devnet-smoke-gate-field fixture "store"))
                             (config
                               (ethereum-lisp.cli::devnet-cli-apply-merge-overrides
                                (devnet-smoke-gate-field fixture "config")
                                :terminal-total-difficulty
                                terminal-total-difficulty
                                :terminal-total-difficulty-passed
                                terminal-total-difficulty-passed-p
                                :terminal-total-difficulty-passed-specified-p
                                terminal-total-difficulty-passed-p
                                :terminal-block-hash terminal-block-hash
                                :terminal-block-number
                                terminal-block-number))
                             (parent-state
                               (devnet-smoke-gate-field fixture
                                                        "parentState"))
                             (parent-block
                               (devnet-smoke-gate-field fixture
                                                        "parentBlock"))
                             (child-block
                               (devnet-smoke-gate-field fixture
                                                        "childBlock"))
                             (payload
                               (devnet-smoke-gate-field fixture "payload"))
                             (side-block
                               (devnet-smoke-gate-field fixture
                                                        "sideBlock"))
                             (side-payload
                               (devnet-smoke-gate-field fixture
                                                        "sidePayload"))
                             (txpool-transactions
                               (devnet-smoke-gate-field
                                fixture "txpoolTransactions"))
                             (pending-transaction
                               (devnet-smoke-gate-txpool-transaction-entry
                                txpool-transactions "pending"))
                             (basefee-transaction
                               (devnet-smoke-gate-txpool-transaction-entry
                                txpool-transactions "basefee"))
                             (queued-transaction
                               (devnet-smoke-gate-txpool-transaction-entry
                                txpool-transactions "queued"))
                             (payload-case
                               (devnet-smoke-gate-field fixture
                                                        "payloadCase"))
                             (expect
                               (devnet-smoke-gate-field fixture "expect"))
                             (node
                               (ethereum-lisp.cli:make-devnet-node
                                :genesis-path
                                (namestring
                                 (devnet-smoke-gate-reference-path
                                  +devnet-cli-genesis-fixture+))
                                :port 8551
                                :public-port 8545
                                :jwt-secret-path (namestring jwt-path)
                                :log-path log-file
                                :database-path database-file
                                :pid-file-path pid-file
                                :txpool-journal-path (namestring journal-path)
                                :txpool-rejournal-seconds 1
                                :terminal-total-difficulty
                                terminal-total-difficulty
                                :terminal-total-difficulty-passed
                                terminal-total-difficulty-passed-p
                                :terminal-total-difficulty-passed-specified-p
                                terminal-total-difficulty-passed-p
                                :terminal-block-hash terminal-block-hash
                                :terminal-block-number terminal-block-number
                                :telemetry-sink telemetry-sink))
                  (expected-terminal-total-difficulty
                    (quantity-to-hex (or terminal-total-difficulty 0)))
                  (expected-terminal-block-hash
                    (hash32-to-hex (or terminal-block-hash (zero-hash32))))
                  (expected-terminal-block-number
                    (quantity-to-hex (or terminal-block-number 0)))
                  (mismatched-terminal-total-difficulty
                    (quantity-to-hex
                     (if (= 1 (or terminal-total-difficulty 0)) 2 1)))
                  (balance-address nil)
                  (expected-balance nil)
                  (balance-field nil)
                  (sender-address nil)
                  (expected-sender-nonce nil)
                  (code-address nil)
                  (expected-code nil)
                  (storage-address nil)
                  (storage-key nil)
                  (expected-storage nil)
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (invalid-token
                    (engine-rpc-make-jwt-token
                     (make-byte-vector 32 :initial-element #x99)
                     0))
                  (unauthenticated-engine-output (make-string-output-stream))
                  (invalid-auth-engine-output (make-string-output-stream))
                  (duplicate-auth-engine-output (make-string-output-stream))
                  (engine-root-wrong-path-output
                    (make-string-output-stream))
                  (client-version-output (make-string-output-stream))
                  (capabilities-output (make-string-output-stream))
                  (transition-configuration-output
                    (make-string-output-stream))
                  (transition-configuration-mismatch-output
                    (make-string-output-stream))
                  (engine-public-namespace-output
                    (make-string-output-stream))
                  (new-payload-output (make-string-output-stream))
                  (forkchoice-output (make-string-output-stream))
                  (payload-bodies-by-hash-output
                    (make-string-output-stream))
                  (payload-bodies-by-range-output
                    (make-string-output-stream))
                  (prepare-payload-output (make-string-output-stream))
                  (get-payload-output (make-string-output-stream))
                  (prepare-txpool-payload-output
                    (make-string-output-stream))
                  (get-txpool-payload-output (make-string-output-stream))
                  (import-txpool-payload-output
                    (make-string-output-stream))
                  (forkchoice-txpool-payload-output
                    (make-string-output-stream))
                  (remote-payload-output (make-string-output-stream))
                  (invalid-payload-output (make-string-output-stream))
                  (block-number-output (make-string-output-stream))
                  (balance-output (make-string-output-stream))
                  (prepared-public-output (make-string-output-stream))
                  (remote-public-output (make-string-output-stream))
                  (invalid-public-output (make-string-output-stream))
                  (public-client-version-output (make-string-output-stream))
                  (public-net-version-output (make-string-output-stream))
                  (public-net-listening-output (make-string-output-stream))
                  (public-syncing-output (make-string-output-stream))
                  (public-net-peer-count-output
                    (make-string-output-stream))
                  (public-accounts-output (make-string-output-stream))
                  (public-coinbase-output (make-string-output-stream))
                  (public-mining-output (make-string-output-stream))
                  (public-hashrate-output (make-string-output-stream))
                  (public-rpc-modules-output (make-string-output-stream))
                  (public-protocol-version-output
                    (make-string-output-stream))
                  (public-web3-sha3-output (make-string-output-stream))
                  (public-gas-price-output (make-string-output-stream))
                  (public-priority-fee-output (make-string-output-stream))
                  (public-base-fee-output (make-string-output-stream))
                  (public-blob-base-fee-output
                    (make-string-output-stream))
                  (public-fee-history-output (make-string-output-stream))
                  (public-batch-output (make-string-output-stream))
                  (public-engine-namespace-output
                    (make-string-output-stream))
                  (public-malformed-json-output
                    (make-string-output-stream))
                  (public-root-wrong-path-output
                    (make-string-output-stream))
                  (new-pending-filter-output
                    (make-string-output-stream))
                  (pending-filter-changes-output
                    (make-string-output-stream))
                  (empty-pending-filter-changes-output
                    (make-string-output-stream))
                  (uninstall-pending-filter-output
                    (make-string-output-stream))
                  (removed-pending-filter-changes-output
                    (make-string-output-stream))
                  (send-raw-output (make-string-output-stream))
                  (send-basefee-output (make-string-output-stream))
                  (send-queued-output (make-string-output-stream))
                  (send-replacement-output (make-string-output-stream))
                  (txpool-rejournal-output (make-string-output-stream))
                  (raw-pending-output (make-string-output-stream))
                  (raw-basefee-output (make-string-output-stream))
                  (raw-queued-output (make-string-output-stream))
                  (pending-nonce-output (make-string-output-stream))
                  (pending-block-receipts-output
                    (make-string-output-stream))
                  (pending-uncle-count-output
                    (make-string-output-stream))
                  (pending-logs-output (make-string-output-stream))
                  (txpool-status-output (make-string-output-stream))
                  (txpool-content-from-output (make-string-output-stream))
                  (txpool-inspect-output (make-string-output-stream))
                  (post-prepared-txpool-content-from-output
                    (make-string-output-stream))
                  (prepare-replacement-txpool-payload-output
                    (make-string-output-stream))
                  (get-replacement-txpool-payload-output
                    (make-string-output-stream))
                  (post-replacement-txpool-content-from-output
                    (make-string-output-stream))
                  (post-import-transaction-output
                    (make-string-output-stream))
                  (post-import-receipt-output
                    (make-string-output-stream))
                  (post-import-raw-output
                    (make-string-output-stream))
                  (post-import-block-output
                    (make-string-output-stream))
                  (post-import-txpool-status-output
                    (make-string-output-stream))
                  (post-import-txpool-content-from-output
                    (make-string-output-stream))
                  (balance-targets
                    (devnet-smoke-gate-balance-targets expect))
                  (checkpoint-balance-targets
                    (devnet-smoke-gate-checkpoint-balance-targets
                     parent-state
                     balance-targets))
                  (transaction-checks
                    (devnet-smoke-gate-transaction-checks child-block))
                  (log-targets
                    (devnet-smoke-gate-log-targets expect))
                  (prepare-payload-attributes
                    (devnet-smoke-gate-payload-attributes-v2
                     child-block
                     (getf (first balance-targets) :address)))
                  (expected-prepared-payload-id
                    (ethereum-lisp.chain-store:engine-payload-id-to-hex
                     (ethereum-lisp.engine-payloads:engine-payload-id
                      2
                      (block-hash child-block)
                      (ethereum-lisp.engine-api::engine-rpc-validate-payload-attributes-v2
                       prepare-payload-attributes))))
                  (txpool-payload-attributes
                    (let ((attributes (copy-tree prepare-payload-attributes)))
                      (setf (cdr (assoc "timestamp" attributes
                                        :test #'string=))
                            (quantity-to-hex
                             (+ 2
                                (block-header-timestamp
                                 (block-header child-block)))))
                      attributes))
                  (remote-block
                    (devnet-smoke-gate-remote-block child-block))
                  (remote-payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data remote-block)))
                  (invalid-block
                    (devnet-smoke-gate-invalid-child-block child-block))
                  (invalid-payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data invalid-block)))
                  (invalid-descendant-block
                    (devnet-smoke-gate-invalid-grandchild-block
                     invalid-block))
                  (invalid-descendant-payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data invalid-descendant-block)))
                  (pending-transaction-hash
                    (transaction-hash pending-transaction))
                  (pending-transaction-hash-hex
                    (hash32-to-hex pending-transaction-hash))
                  (replacement-transaction
                    (devnet-smoke-gate-txpool-transaction
                     config
                     (transaction-nonce pending-transaction)
                     +devnet-smoke-gate-txpool-replacement-gas-price+))
                  (replacement-transaction-hash
                    (transaction-hash replacement-transaction))
                  (replacement-transaction-hash-hex
                    (hash32-to-hex replacement-transaction-hash))
                  (basefee-transaction-hash-hex
                    (devnet-smoke-gate-transaction-hash-hex
                     basefee-transaction))
                  (queued-transaction-hash-hex
                    (devnet-smoke-gate-transaction-hash-hex
                     queued-transaction))
                  (pending-transaction-raw
                    (devnet-smoke-gate-transaction-raw
                     pending-transaction))
                  (replacement-transaction-raw
                    (devnet-smoke-gate-transaction-raw
                     replacement-transaction))
                  (basefee-transaction-raw
                    (devnet-smoke-gate-transaction-raw
                     basefee-transaction))
                  (queued-transaction-raw
                    (devnet-smoke-gate-transaction-raw
                     queued-transaction))
                  (pending-transaction-summary
                    (devnet-smoke-gate-transaction-summary
                     pending-transaction))
                  (basefee-transaction-summary
                    (devnet-smoke-gate-transaction-summary
                     basefee-transaction))
                  (queued-transaction-summary
                    (devnet-smoke-gate-transaction-summary
                     queued-transaction))
                  (pending-transaction-sender
                    (transaction-sender pending-transaction))
                  (pending-transaction-sender-hex
                    (address-to-hex pending-transaction-sender))
                  (pending-transaction-nonce-key
                    (devnet-smoke-gate-transaction-nonce-key
                     pending-transaction))
                  (expected-pending-sender-nonce
                    (quantity-to-hex
                     (1+ (transaction-nonce pending-transaction))))
                  (basefee-transaction-nonce-key
                    (devnet-smoke-gate-transaction-nonce-key
                     basefee-transaction))
                  (queued-transaction-nonce-key
                    (devnet-smoke-gate-transaction-nonce-key
                     queued-transaction))
                  (txpool-rejournal-report nil)
                  (prepare-txpool-payload-response-cache nil)
                  (get-txpool-payload-response-cache nil)
                  (post-public-txpool-payload-id nil)
                  (post-public-txpool-execution-payload nil)
                  (post-public-txpool-block-hash nil)
                  (prepare-replacement-txpool-payload-response-cache nil)
                  (get-replacement-txpool-payload-response-cache nil)
                  (replacement-txpool-payload-id nil)
                  (replacement-txpool-execution-payload nil)
                  (replacement-txpool-block-hash nil)
                  (engine-requests
                    (list
                     (cons
                      (json-encode
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 18)
                        (cons "method" "engine_getClientVersionV1")
                        (cons "params"
                              (list
                               (list
                                (cons "code" "CL")
                                (cons "name" "ethereum-lisp-smoke")
                                (cons "version" "0.0.0")
                                (cons "commit" "0x00000000"))))))
                      client-version-output)
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 19)
                             (cons "method" "engine_exchangeCapabilities")
                             (cons "params"
                                   (list
                                    (vector
                                     "engine_newPayloadV1"
                                     "engine_forkchoiceUpdatedV1"
                                     "engine_getPayloadV1"
                                     "engine_newPayloadV2"
                                     "engine_forkchoiceUpdatedV2"
                                     "engine_getPayloadV2")))))
                      capabilities-output)
                     (cons
                      (json-encode
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 27)
                        (cons "method"
                              "engine_exchangeTransitionConfigurationV1")
                        (cons "params"
                              (list
                               (list
                                (cons "terminalTotalDifficulty"
                                      expected-terminal-total-difficulty)
                                (cons "terminalBlockHash"
                                      expected-terminal-block-hash)
                                (cons "terminalBlockNumber"
                                      expected-terminal-block-number))))))
                      transition-configuration-output)
                     (cons
                      (json-encode
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 28)
                        (cons "method"
                              "engine_exchangeTransitionConfigurationV1")
                        (cons "params"
                              (list
                               (list
                                (cons "terminalTotalDifficulty"
                                      mismatched-terminal-total-difficulty)
                                (cons "terminalBlockHash"
                                      expected-terminal-block-hash)
                                (cons "terminalBlockNumber"
                                      expected-terminal-block-number))))))
                      transition-configuration-mismatch-output)
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 71)
                             (cons "method" "eth_chainId")
                             (cons "params" #())))
                      engine-public-namespace-output)
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 21 payload))
                      new-payload-output)
                     (cons
                      (json-encode
                       (devnet-cli-engine-forkchoice-v2-request
                        22 (block-hash child-block)
                        :safe (block-hash parent-block)
                        :finalized (block-hash parent-block)))
                      forkchoice-output)
                     (cons
                      (json-encode
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 28)
                        (cons "method" "engine_getPayloadBodiesByHashV1")
                        (cons "params"
                              (list
                               (vector
                                (hash32-to-hex (block-hash child-block)))))))
                      payload-bodies-by-hash-output)
                     (cons
                      (json-encode
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 29)
                        (cons "method" "engine_getPayloadBodiesByRangeV1")
                        (cons "params"
                              (list
                               (quantity-to-hex
                                (block-header-number
                                 (block-header child-block)))
                               "0x1"))))
                      payload-bodies-by-range-output)
                     (cons
                      (json-encode
                       (devnet-smoke-gate-forkchoice-v2-payload-attributes-request
                        23
                        (block-hash child-block)
                        prepare-payload-attributes
                        :safe (block-hash parent-block)
                        :finalized (block-hash parent-block)))
                      prepare-payload-output)
                     (cons
                      (json-encode
                       (list
                        (cons "jsonrpc" "2.0")
                        (cons "id" 30)
                        (cons "method" "engine_getPayloadV2")
                        (cons "params"
                              (list expected-prepared-payload-id))))
                      get-payload-output)
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 24 remote-payload))
                      remote-payload-output)
                     (cons
                      (json-encode
                       (engine-fixture-payload-request 25 invalid-payload))
                      invalid-payload-output)))
                  (post-public-engine-requests
                    (list
                     (cons
                      (json-encode
                       (devnet-smoke-gate-forkchoice-v2-payload-attributes-request
                        78
                        (block-hash child-block)
                        txpool-payload-attributes
                        :safe (block-hash parent-block)
                        :finalized (block-hash parent-block)))
                      prepare-txpool-payload-output)
                     (cons
                      :txpool-get-payload
                      get-txpool-payload-output)))
                  (replacement-engine-requests
                    (list
                     (cons
                      (json-encode
                       (devnet-smoke-gate-forkchoice-v2-payload-attributes-request
                        89
                        (block-hash child-block)
                        txpool-payload-attributes
                        :safe (block-hash parent-block)
                        :finalized (block-hash parent-block)))
                      prepare-replacement-txpool-payload-output)
                     (cons
                      :replacement-txpool-get-payload
                      get-replacement-txpool-payload-output)))
                  (post-prepared-engine-requests
                    (list
                     (cons
                      :txpool-new-payload
                      import-txpool-payload-output)
                     (cons
                      :txpool-forkchoice
                      forkchoice-txpool-payload-output)))
                  (public-requests
                    (let ((target (first balance-targets)))
                      (setf balance-address (getf target :address)
                            expected-balance (getf target :balance)
                            balance-field (getf target :field)
                            sender-address
                            (fixture-address-field expect "sender")
                            expected-sender-nonce
                            (fixture-object-field expect "senderNonce")
                            code-address
                            (fixture-address-field expect "codeAddress")
                            expected-code
                            (fixture-object-field expect "code")
                            storage-address
                            (fixture-address-field expect "storageAddress")
                            storage-key
                            (fixture-object-field expect "storageKey")
                            expected-storage
                            (fixture-object-field expect "storageValue"))
                      (list
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 31)
                               (cons "method" "eth_blockNumber")
                               (cons "params" #())))
                        block-number-output)
                       (cons
                        (json-encode
                         (engine-fixture-balance-request 32 balance-address))
                        balance-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 33)
                               (cons "method" "eth_blockNumber")
                               (cons "params" #())))
                        prepared-public-output)
                       (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                               (cons "id" 34)
                               (cons "method" "eth_blockNumber")
                               (cons "params" #())))
                        remote-public-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 35)
                               (cons "method" "eth_blockNumber")
                               (cons "params" #())))
                        invalid-public-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 46)
                               (cons "method" "web3_clientVersion")
                               (cons "params" #())))
                        public-client-version-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 47)
                               (cons "method" "net_version")
                               (cons "params" #())))
                        public-net-version-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 48)
                               (cons "method" "net_listening")
                               (cons "params" #())))
                        public-net-listening-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 49)
                               (cons "method" "eth_syncing")
                               (cons "params" #())))
                        public-syncing-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 53)
                               (cons "method" "net_peerCount")
                               (cons "params" #())))
                        public-net-peer-count-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 54)
                               (cons "method" "eth_accounts")
                               (cons "params" #())))
                        public-accounts-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 55)
                               (cons "method" "eth_coinbase")
                               (cons "params" #())))
                        public-coinbase-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 56)
                               (cons "method" "eth_mining")
                               (cons "params" #())))
                        public-mining-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 57)
                               (cons "method" "eth_hashrate")
                               (cons "params" #())))
                        public-hashrate-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 58)
                               (cons "method" "rpc_modules")
                               (cons "params" #())))
                        public-rpc-modules-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 59)
                               (cons "method" "eth_protocolVersion")
                               (cons "params" #())))
                        public-protocol-version-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 60)
                               (cons "method" "web3_sha3")
                               (cons "params" (list "0x68656c6c6f"))))
                        public-web3-sha3-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 61)
                               (cons "method" "eth_gasPrice")
                               (cons "params" #())))
                        public-gas-price-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 62)
                               (cons "method" "eth_maxPriorityFeePerGas")
                               (cons "params" #())))
                        public-priority-fee-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 63)
                               (cons "method" "eth_baseFee")
                               (cons "params" #())))
                        public-base-fee-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 64)
                               (cons "method" "eth_blobBaseFee")
                               (cons "params" #())))
                        public-blob-base-fee-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 65)
                               (cons "method" "eth_feeHistory")
                               (cons "params" (list "0x1" "latest" #()))))
                        public-fee-history-output)
                       (cons
                        (json-encode
                         (list
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 50)
                                (cons "method" "eth_chainId")
                                (cons "params" #()))
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 51)
                                (cons "method" "net_version")
                                (cons "params" #()))
                          (list (cons "jsonrpc" "2.0")
                                (cons "id" 52)
                                (cons "method" "web3_clientVersion")
                                (cons "params" #()))))
                        public-batch-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 45)
                               (cons "method" "engine_exchangeCapabilities")
                               (cons "params" (list #()))))
                        public-engine-namespace-output)
                       (cons "{" public-malformed-json-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 66)
                               (cons "method"
                                     "eth_newPendingTransactionFilter")
                               (cons "params" #())))
                        new-pending-filter-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 36)
                               (cons "method" "eth_sendRawTransaction")
                               (cons "params"
                                     (list pending-transaction-raw))))
                        send-raw-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 37)
                               (cons "method" "eth_sendRawTransaction")
                               (cons "params"
                                     (list basefee-transaction-raw))))
                        send-basefee-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 38)
                               (cons "method" "eth_sendRawTransaction")
                               (cons "params"
                                     (list queued-transaction-raw))))
                        send-queued-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 77)
                               (cons "method" "eth_blockNumber")
                               (cons "params" #())))
                        txpool-rejournal-output)
                       (cons
                       (json-encode
                        (list (cons "jsonrpc" "2.0")
                              (cons "id" 67)
                              (cons "method" "eth_getFilterChanges")
                              (cons "params" (list "0x1"))))
                        pending-filter-changes-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 68)
                               (cons "method" "eth_getFilterChanges")
                               (cons "params" (list "0x1"))))
                        empty-pending-filter-changes-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 69)
                               (cons "method" "eth_uninstallFilter")
                               (cons "params" (list "0x1"))))
                        uninstall-pending-filter-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 70)
                               (cons "method" "eth_getFilterChanges")
                               (cons "params" (list "0x1"))))
                        removed-pending-filter-changes-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 39)
                               (cons "method" "eth_getRawTransactionByHash")
                               (cons "params"
                                     (list pending-transaction-hash-hex))))
                        raw-pending-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 40)
                               (cons "method" "eth_getRawTransactionByHash")
                               (cons "params"
                                     (list basefee-transaction-hash-hex))))
                        raw-basefee-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 41)
                               (cons "method" "eth_getRawTransactionByHash")
                               (cons "params"
                                     (list queued-transaction-hash-hex))))
                        raw-queued-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 46)
                               (cons "method" "eth_getTransactionCount")
                               (cons "params"
                                     (list pending-transaction-sender-hex
                                           "pending"))))
                        pending-nonce-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 74)
                               (cons "method" "eth_getBlockReceipts")
                               (cons "params" (list "pending"))))
                        pending-block-receipts-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 75)
                               (cons "method"
                                     "eth_getUncleCountByBlockNumber")
                               (cons "params" (list "pending"))))
                        pending-uncle-count-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 76)
                               (cons "method" "eth_getLogs")
                               (cons "params"
                                     (list
                                      (list
                                       (cons "fromBlock" "pending")
                                       (cons "toBlock" "pending"))))))
                        pending-logs-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 42)
                               (cons "method" "txpool_status")
                               (cons "params" #())))
                        txpool-status-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 43)
                               (cons "method" "txpool_contentFrom")
                               (cons "params"
                                     (list pending-transaction-sender-hex))))
                        txpool-content-from-output)
                       (cons
                        (json-encode
                         (list (cons "jsonrpc" "2.0")
                               (cons "id" 44)
                               (cons "method" "txpool_inspect")
                               (cons "params" #())))
                        txpool-inspect-output))))
                  (engine-served-count 0)
                  (unauthenticated-engine-served-p nil)
                  (invalid-auth-engine-served-p nil)
                  (duplicate-auth-engine-served-p nil)
                  (engine-root-wrong-path-served-p nil)
                  (engine-pre-txpool-done-p nil)
                  (engine-prepared-txpool-done-p nil)
                  (engine-replacement-prepared-txpool-done-p nil)
                  (engine-done-p nil)
                  (public-served-count 0)
                  (public-txpool-done-p nil)
                  (post-prepared-txpool-content-served-p nil)
                  (replacement-send-served-p nil)
                  (post-replacement-txpool-content-served-p nil)
                  (post-import-public-requests
                    (list
                     (cons :txpool-import-transaction
                           post-import-transaction-output)
                     (cons :txpool-import-receipt
                           post-import-receipt-output)
                     (cons :txpool-import-raw
                           post-import-raw-output)
                     (cons :txpool-import-block
                           post-import-block-output)
                     (cons :txpool-import-status
                           post-import-txpool-status-output)
                     (cons :txpool-import-content-from
                           post-import-txpool-content-from-output)))
                  (public-root-wrong-path-served-p nil))
             (devnet-cli-set-node-store-config node store config)
             (engine-payload-store-put-block
              store parent-block :state-available-p t)
             (commit-state-db-to-chain-store
              store (block-hash parent-block) parent-state)
             (when pid-file
               (ethereum-lisp.cli::devnet-cli-write-pid-file pid-file))
             (let ((summary
                     (ethereum-lisp.cli:start-devnet-node-listeners
                      node
                      (make-engine-rpc-http-listener
                       :endpoint +devnet-smoke-gate-engine-endpoint+
                       :accept-function
                       (lambda ()
                         (cond
                           ((not unauthenticated-engine-served-p)
                            (setf unauthenticated-engine-served-p t)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 20)
                                 (cons "method"
                                       "engine_getClientVersionV1")
                                 (cons "params"
                                       (list ethereum-lisp.json:+json-empty-object+))))))
                             :output-stream unauthenticated-engine-output
                             :close-function
                             (lambda ()
                               (incf engine-served-count))))
                           ((not invalid-auth-engine-served-p)
                            (setf invalid-auth-engine-served-p t)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 26)
                                 (cons "method"
                                       "engine_getClientVersionV1")
                                 (cons "params"
                                       (list ethereum-lisp.json:+json-empty-object+))))
                               :token invalid-token))
                             :output-stream invalid-auth-engine-output
                             :close-function
                             (lambda ()
                               (incf engine-served-count))))
                           ((not duplicate-auth-engine-served-p)
                            (setf duplicate-auth-engine-served-p t)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-duplicate-auth-http-request
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 45)
                                 (cons "method"
                                       "engine_getClientVersionV1")
                                 (cons "params"
                                       (list ethereum-lisp.json:+json-empty-object+))))
                               token invalid-token))
                             :output-stream duplicate-auth-engine-output
                             :close-function
                             (lambda ()
                               (incf engine-served-count))))
                           ((not engine-root-wrong-path-served-p)
                            (setf engine-root-wrong-path-served-p t)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 72)
                                 (cons "method"
                                       "engine_getClientVersionV1")
                                 (cons "params"
                                       (list ethereum-lisp.json:+json-empty-object+))))
                               :token token
                               :target "/unexpected"))
                             :output-stream engine-root-wrong-path-output
                             :close-function
                             (lambda ()
                               (incf engine-served-count))))
                           (engine-requests
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
                                (unless engine-requests
                                  (setf engine-pre-txpool-done-p t))))))
                           (post-public-engine-requests
                            (loop until public-txpool-done-p
                                  do (sleep 0.001))
                            (destructuring-bind (body . output)
                                (pop post-public-engine-requests)
                              (let ((request-body
                                      (if (eq body :txpool-get-payload)
                                          (json-encode
                                           (list
                                            (cons "jsonrpc" "2.0")
                                            (cons "id" 79)
                                            (cons "method"
                                                  "engine_getPayloadV2")
                                            (cons "params"
                                                  (list
                                                   post-public-txpool-payload-id))))
                                          body)))
                                (make-engine-rpc-http-connection
                                 :input-stream
                                 (make-string-input-stream
                                  (devnet-cli-json-rpc-http-request
                                   request-body :token token))
                                 :output-stream output
                                 :close-function
                                 (lambda ()
                                   (incf engine-served-count)
                                   (when (eq output
                                             prepare-txpool-payload-output)
                                     (setf
                                      prepare-txpool-payload-response-cache
                                      (get-output-stream-string
                                       prepare-txpool-payload-output)
                                      post-public-txpool-payload-id
                                      (fixture-object-field
                                       (fixture-object-field
                                        (devnet-smoke-gate-rpc-body
                                         prepare-txpool-payload-response-cache)
                                        "result")
                                       "payloadId")))
                                   (when (eq output
                                             get-txpool-payload-output)
                                     (setf
                                      get-txpool-payload-response-cache
                                      (get-output-stream-string
                                       get-txpool-payload-output)
                                      post-public-txpool-execution-payload
                                      (fixture-object-field
                                       (fixture-object-field
                                        (devnet-smoke-gate-rpc-body
                                         get-txpool-payload-response-cache
                                         :preserve-empty-arrays t)
                                        "result")
                                       "executionPayload")
                                      post-public-txpool-block-hash
                                      (fixture-object-field
                                       post-public-txpool-execution-payload
                                       "blockHash")))
                                   (unless post-public-engine-requests
                                     (setf
                                      engine-prepared-txpool-done-p
                                      t)))))))
                           (replacement-engine-requests
                            (loop until replacement-send-served-p
                                  do (sleep 0.001))
                            (destructuring-bind (body . output)
                                (pop replacement-engine-requests)
                              (let ((request-body
                                      (if (eq body
                                              :replacement-txpool-get-payload)
                                          (json-encode
                                           (list
                                            (cons "jsonrpc" "2.0")
                                            (cons "id" 90)
                                            (cons "method"
                                                  "engine_getPayloadV2")
                                            (cons "params"
                                                  (list
                                                   replacement-txpool-payload-id))))
                                          body)))
                                (make-engine-rpc-http-connection
                                 :input-stream
                                 (make-string-input-stream
                                  (devnet-cli-json-rpc-http-request
                                   request-body :token token))
                                 :output-stream output
                                 :close-function
                                 (lambda ()
                                   (incf engine-served-count)
                                   (when (eq output
                                             prepare-replacement-txpool-payload-output)
                                     (setf
                                      prepare-replacement-txpool-payload-response-cache
                                      (get-output-stream-string
                                       prepare-replacement-txpool-payload-output)
                                      replacement-txpool-payload-id
                                      (fixture-object-field
                                       (fixture-object-field
                                        (devnet-smoke-gate-rpc-body
                                         prepare-replacement-txpool-payload-response-cache)
                                        "result")
                                       "payloadId")))
                                   (when (eq output
                                             get-replacement-txpool-payload-output)
                                     (setf
                                      get-replacement-txpool-payload-response-cache
                                      (get-output-stream-string
                                       get-replacement-txpool-payload-output)
                                      replacement-txpool-execution-payload
                                      (fixture-object-field
                                       (fixture-object-field
                                        (devnet-smoke-gate-rpc-body
                                         get-replacement-txpool-payload-response-cache
                                         :preserve-empty-arrays t)
                                        "result")
                                       "executionPayload")
                                      replacement-txpool-block-hash
                                      (fixture-object-field
                                       replacement-txpool-execution-payload
                                       "blockHash")))
                                   (unless replacement-engine-requests
                                     (setf
                                      engine-replacement-prepared-txpool-done-p
                                      t)))))))
                           (post-prepared-engine-requests
                            (loop until post-replacement-txpool-content-served-p
                                  do (sleep 0.001))
                            (destructuring-bind (body . output)
                                (pop post-prepared-engine-requests)
                              (let ((request-body
                                      (cond
                                        ((eq body :txpool-new-payload)
                                         (devnet-smoke-gate-json-rpc-request
                                          81
                                          "engine_newPayloadV2"
                                          (list
                                           replacement-txpool-execution-payload)))
                                        ((eq body :txpool-forkchoice)
                                         (json-encode
                                          (devnet-cli-engine-forkchoice-v2-request
                                           82
                                           (hash32-from-hex
                                            replacement-txpool-block-hash)
                                           :safe (block-hash parent-block)
                                           :finalized
                                           (block-hash parent-block))))
                                        (t body))))
                                (make-engine-rpc-http-connection
                                 :input-stream
                                 (make-string-input-stream
                                  (devnet-cli-json-rpc-http-request
                                   request-body :token token))
                                 :output-stream output
                                 :close-function
                                 (lambda ()
                                   (incf engine-served-count)
                                   (unless post-prepared-engine-requests
                                     (setf engine-done-p t)))))))))
                       :close-function (lambda () nil))
                      (make-engine-rpc-http-listener
                       :endpoint +devnet-smoke-gate-public-endpoint+
                       :accept-function
                       (lambda ()
                         (loop until engine-pre-txpool-done-p
                               do (sleep 0.001))
                         (cond
                           ((not public-root-wrong-path-served-p)
                            (setf public-root-wrong-path-served-p t)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list
                                 (cons "jsonrpc" "2.0")
                                 (cons "id" 73)
                                 (cons "method" "eth_chainId")
                                 (cons "params" #())))
                               :target "/unexpected"))
                             :output-stream public-root-wrong-path-output
                             :close-function
                             (lambda () (incf public-served-count))))
                           (public-requests
                            (destructuring-bind (body . output)
                                (pop public-requests)
                              (when (eq output txpool-rejournal-output)
                                (setf txpool-rejournal-report
                                      (devnet-smoke-gate-wait-for-txpool-journal-record
                                       journal-path
                                       pending-transaction-hash-hex
                                       pending-transaction-raw
                                       5
                                       :expected-record-count 3)))
                              (make-engine-rpc-http-connection
                               :input-stream
                               (make-string-input-stream
                                (devnet-cli-json-rpc-http-request body))
                               :output-stream output
                               :close-function
                               (lambda () (incf public-served-count)))))
                           ((not post-prepared-txpool-content-served-p)
                            (setf public-txpool-done-p t)
                            (loop until engine-prepared-txpool-done-p
                                  do (sleep 0.001))
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list (cons "jsonrpc" "2.0")
                                      (cons "id" 80)
                                      (cons "method" "txpool_contentFrom")
                                      (cons "params"
                                            (list pending-transaction-sender-hex))))))
                             :output-stream
                             post-prepared-txpool-content-from-output
                             :close-function
                             (lambda ()
                               (incf public-served-count)
                               (setf
                                post-prepared-txpool-content-served-p
                                t))))
                           ((not replacement-send-served-p)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list (cons "jsonrpc" "2.0")
                                      (cons "id" 91)
                                      (cons "method"
                                            "eth_sendRawTransaction")
                                      (cons "params"
                                            (list replacement-transaction-raw))))))
                             :output-stream send-replacement-output
                             :close-function
                             (lambda ()
                               (incf public-served-count)
                               (setf replacement-send-served-p t))))
                           ((not post-replacement-txpool-content-served-p)
                            (loop until engine-replacement-prepared-txpool-done-p
                                  do (sleep 0.001))
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream
                              (devnet-cli-json-rpc-http-request
                               (json-encode
                                (list (cons "jsonrpc" "2.0")
                                      (cons "id" 92)
                                      (cons "method" "txpool_contentFrom")
                                      (cons "params"
                                            (list pending-transaction-sender-hex))))))
                             :output-stream
                             post-replacement-txpool-content-from-output
                             :close-function
                             (lambda ()
                               (incf public-served-count)
                               (setf
                                post-replacement-txpool-content-served-p
                                t))))
                           (post-import-public-requests
                            (loop until engine-done-p
                                  do (sleep 0.001))
                            (destructuring-bind (body . output)
                                (pop post-import-public-requests)
                              (let ((request-body
                                      (case body
                                        (:txpool-import-transaction
                                         (devnet-smoke-gate-json-rpc-request
                                          83
                                          "eth_getTransactionByHash"
                                          (list replacement-transaction-hash-hex)))
                                        (:txpool-import-receipt
                                         (devnet-smoke-gate-json-rpc-request
                                          84
                                          "eth_getTransactionReceipt"
                                          (list replacement-transaction-hash-hex)))
                                        (:txpool-import-raw
                                         (devnet-smoke-gate-json-rpc-request
                                          85
                                          "eth_getRawTransactionByHash"
                                          (list replacement-transaction-hash-hex)))
                                        (:txpool-import-block
                                         (devnet-smoke-gate-json-rpc-request
                                          86
                                          "eth_getBlockByHash"
                                          (list replacement-txpool-block-hash
                                                :false)))
                                        (:txpool-import-status
                                         (devnet-smoke-gate-json-rpc-request
                                          87
                                          "txpool_status"
                                          '()))
                                        (:txpool-import-content-from
                                         (devnet-smoke-gate-json-rpc-request
                                          88
                                          "txpool_contentFrom"
                                          (list pending-transaction-sender-hex)))
                                        (otherwise body))))
                                (make-engine-rpc-http-connection
                                 :input-stream
                                 (make-string-input-stream
                                  (devnet-cli-json-rpc-http-request
                                   request-body))
                                 :output-stream output
                                 :close-function
                                 (lambda ()
                                   (incf public-served-count))))))))
                      :close-function (lambda () nil))
                      :max-connections
                      +devnet-smoke-gate-public-connections+
                      :on-listeners-ready
                      (lambda (engine-listener public-listener)
                        (let ((engine-endpoint
                                (engine-rpc-http-listener-endpoint
                                 engine-listener))
                              (rpc-endpoint
                                (engine-rpc-http-listener-endpoint
                                 public-listener)))
                          (when ready-file
                            (ethereum-lisp.cli::devnet-cli-write-ready-file
                             node
                             ready-file
                             :engine-endpoint engine-endpoint
                             :rpc-endpoint rpc-endpoint))
                          (when log-file
                            (ethereum-lisp.cli::devnet-cli-log-event
                             node
                             "devnet.ready"
                            :engine-endpoint engine-endpoint
                            :rpc-endpoint rpc-endpoint)))))))
               (devnet-smoke-gate-require
                (= +devnet-smoke-gate-engine-connections+
                   (getf summary :engine-connections))
                "Devnet smoke gate Engine connection count mismatch")
               (devnet-smoke-gate-require
                (= +devnet-smoke-gate-public-connections+
                   (getf summary :public-connections))
                "Devnet smoke gate public connection count mismatch")
               (devnet-smoke-gate-require
                (= +devnet-smoke-gate-total-connections+
                   (getf summary :total-connections))
                "Devnet smoke gate total connection count mismatch")
               (when log-file
                 (ethereum-lisp.cli::devnet-cli-log-event
                  node
                  "devnet.shutdown"
                  :engine-endpoint +devnet-smoke-gate-engine-endpoint+
                  :rpc-endpoint +devnet-smoke-gate-public-endpoint+
                  :connection-summary summary))
               (let* ((capabilities-response
                        (get-output-stream-string capabilities-output))
                      (client-version-response
                        (get-output-stream-string client-version-output))
                      (transition-configuration-response
                        (get-output-stream-string
                         transition-configuration-output))
                      (transition-configuration-mismatch-response
                        (get-output-stream-string
                         transition-configuration-mismatch-output))
                      (engine-public-namespace-response
                        (get-output-stream-string
                         engine-public-namespace-output))
                      (new-payload-response
                        (get-output-stream-string new-payload-output))
                      (unauthenticated-engine-response
                        (get-output-stream-string
                         unauthenticated-engine-output))
                      (invalid-auth-engine-response
                        (get-output-stream-string
                         invalid-auth-engine-output))
                      (duplicate-auth-engine-response
                        (get-output-stream-string
                         duplicate-auth-engine-output))
                      (engine-root-wrong-path-response
                        (get-output-stream-string
                         engine-root-wrong-path-output))
                      (forkchoice-response
                        (get-output-stream-string forkchoice-output))
                      (payload-bodies-by-hash-response
                        (get-output-stream-string
                         payload-bodies-by-hash-output))
                      (payload-bodies-by-range-response
                        (get-output-stream-string
                         payload-bodies-by-range-output))
                      (prepare-payload-response
                        (get-output-stream-string prepare-payload-output))
                      (get-payload-response
                        (get-output-stream-string get-payload-output))
                      (prepare-txpool-payload-response
                        (or prepare-txpool-payload-response-cache
                            (get-output-stream-string
                             prepare-txpool-payload-output)))
                      (get-txpool-payload-response
                        (or get-txpool-payload-response-cache
                            (get-output-stream-string
                             get-txpool-payload-output)))
                      (import-txpool-payload-response
                        (get-output-stream-string
                         import-txpool-payload-output))
                      (forkchoice-txpool-payload-response
                        (get-output-stream-string
                         forkchoice-txpool-payload-output))
                      (remote-payload-response
                        (get-output-stream-string remote-payload-output))
                      (invalid-payload-response
                        (get-output-stream-string invalid-payload-output))
                      (block-number-response
                        (get-output-stream-string block-number-output))
                      (balance-response
                        (get-output-stream-string balance-output))
                      (prepared-public-response
                        (get-output-stream-string prepared-public-output))
                      (remote-public-response
                        (get-output-stream-string remote-public-output))
                      (invalid-public-response
                        (get-output-stream-string invalid-public-output))
                      (public-client-version-response
                        (get-output-stream-string
                         public-client-version-output))
                      (public-net-version-response
                        (get-output-stream-string public-net-version-output))
                      (public-net-listening-response
                        (get-output-stream-string
                         public-net-listening-output))
                      (public-syncing-response
                        (get-output-stream-string public-syncing-output))
                      (public-net-peer-count-response
                        (get-output-stream-string
                         public-net-peer-count-output))
                      (public-accounts-response
                        (get-output-stream-string public-accounts-output))
                      (public-coinbase-response
                        (get-output-stream-string public-coinbase-output))
                      (public-mining-response
                        (get-output-stream-string public-mining-output))
                      (public-hashrate-response
                        (get-output-stream-string public-hashrate-output))
                      (public-rpc-modules-response
                        (get-output-stream-string
                         public-rpc-modules-output))
                      (public-protocol-version-response
                        (get-output-stream-string
                         public-protocol-version-output))
                      (public-web3-sha3-response
                        (get-output-stream-string public-web3-sha3-output))
                      (public-gas-price-response
                        (get-output-stream-string public-gas-price-output))
                      (public-priority-fee-response
                        (get-output-stream-string public-priority-fee-output))
                      (public-base-fee-response
                        (get-output-stream-string public-base-fee-output))
                      (public-blob-base-fee-response
                        (get-output-stream-string public-blob-base-fee-output))
                      (public-fee-history-response
                        (get-output-stream-string public-fee-history-output))
                      (public-batch-response
                        (get-output-stream-string public-batch-output))
                      (public-engine-namespace-response
                        (get-output-stream-string
                         public-engine-namespace-output))
                      (public-malformed-json-response
                        (get-output-stream-string
                         public-malformed-json-output))
                      (public-root-wrong-path-response
                        (get-output-stream-string
                         public-root-wrong-path-output))
                      (new-pending-filter-response
                        (get-output-stream-string new-pending-filter-output))
                      (pending-filter-changes-response
                        (get-output-stream-string
                         pending-filter-changes-output))
                      (empty-pending-filter-changes-response
                        (get-output-stream-string
                         empty-pending-filter-changes-output))
                      (uninstall-pending-filter-response
                        (get-output-stream-string
                         uninstall-pending-filter-output))
                      (removed-pending-filter-changes-response
                        (get-output-stream-string
                         removed-pending-filter-changes-output))
                      (send-raw-response
                        (get-output-stream-string send-raw-output))
                      (send-basefee-response
                        (get-output-stream-string send-basefee-output))
                      (send-queued-response
                        (get-output-stream-string send-queued-output))
                      (send-replacement-response
                        (get-output-stream-string send-replacement-output))
                      (txpool-rejournal-response
                        (get-output-stream-string txpool-rejournal-output))
                      (raw-pending-response
                        (get-output-stream-string raw-pending-output))
                      (raw-basefee-response
                        (get-output-stream-string raw-basefee-output))
                      (raw-queued-response
                        (get-output-stream-string raw-queued-output))
                      (pending-nonce-response
                        (get-output-stream-string pending-nonce-output))
                      (pending-block-receipts-response
                        (get-output-stream-string
                         pending-block-receipts-output))
                      (pending-uncle-count-response
                        (get-output-stream-string pending-uncle-count-output))
                      (pending-logs-response
                        (get-output-stream-string pending-logs-output))
                      (txpool-status-response
                        (get-output-stream-string txpool-status-output))
                      (txpool-content-from-response
                        (get-output-stream-string
                         txpool-content-from-output))
                      (txpool-inspect-response
                        (get-output-stream-string txpool-inspect-output))
                      (post-prepared-txpool-content-from-response
                        (get-output-stream-string
                         post-prepared-txpool-content-from-output))
                      (prepare-replacement-txpool-payload-response
                        (or prepare-replacement-txpool-payload-response-cache
                            (get-output-stream-string
                             prepare-replacement-txpool-payload-output)))
                      (get-replacement-txpool-payload-response
                        (or get-replacement-txpool-payload-response-cache
                            (get-output-stream-string
                             get-replacement-txpool-payload-output)))
                      (post-replacement-txpool-content-from-response
                        (get-output-stream-string
                         post-replacement-txpool-content-from-output))
                      (post-import-transaction-response
                        (get-output-stream-string
                         post-import-transaction-output))
                      (post-import-receipt-response
                        (get-output-stream-string
                         post-import-receipt-output))
                      (post-import-raw-response
                        (get-output-stream-string
                         post-import-raw-output))
                      (post-import-block-response
                        (get-output-stream-string
                         post-import-block-output))
                      (post-import-txpool-status-response
                        (get-output-stream-string
                         post-import-txpool-status-output))
                      (post-import-txpool-content-from-response
                        (get-output-stream-string
                         post-import-txpool-content-from-output))
                      (capabilities-rpc
                        (devnet-smoke-gate-rpc-body capabilities-response))
                      (client-version-rpc
                        (devnet-smoke-gate-rpc-body
                         client-version-response))
                      (transition-configuration-rpc
                        (devnet-smoke-gate-rpc-body
                         transition-configuration-response))
                      (transition-configuration-mismatch-rpc
                        (devnet-smoke-gate-rpc-body
                         transition-configuration-mismatch-response))
                      (engine-public-namespace-rpc
                        (devnet-smoke-gate-rpc-body
                         engine-public-namespace-response))
                      (new-payload-rpc
                        (devnet-smoke-gate-rpc-body new-payload-response))
                      (forkchoice-rpc
                        (devnet-smoke-gate-rpc-body forkchoice-response))
                      (payload-bodies-by-hash-rpc
                        (devnet-smoke-gate-rpc-body
                         payload-bodies-by-hash-response))
                      (payload-bodies-by-range-rpc
                        (devnet-smoke-gate-rpc-body
                         payload-bodies-by-range-response))
                      (prepare-payload-rpc
                        (devnet-smoke-gate-rpc-body prepare-payload-response))
                      (get-payload-rpc
                        (devnet-smoke-gate-rpc-body get-payload-response))
                      (prepare-txpool-payload-rpc
                        (devnet-smoke-gate-rpc-body
                         prepare-txpool-payload-response))
                      (get-txpool-payload-rpc
                        (devnet-smoke-gate-rpc-body
                         get-txpool-payload-response))
                      (import-txpool-payload-rpc
                        (devnet-smoke-gate-rpc-body
                         import-txpool-payload-response))
                      (forkchoice-txpool-payload-rpc
                        (devnet-smoke-gate-rpc-body
                         forkchoice-txpool-payload-response))
                      (remote-payload-rpc
                        (devnet-smoke-gate-rpc-body remote-payload-response))
                      (invalid-payload-rpc
                        (devnet-smoke-gate-rpc-body invalid-payload-response))
                      (block-number-rpc
                        (devnet-smoke-gate-rpc-body block-number-response))
                      (balance-rpc
                        (devnet-smoke-gate-rpc-body balance-response))
                      (prepared-public-rpc
                        (devnet-smoke-gate-rpc-body prepared-public-response))
                      (remote-public-rpc
                        (devnet-smoke-gate-rpc-body remote-public-response))
                      (invalid-public-rpc
                        (devnet-smoke-gate-rpc-body invalid-public-response))
                      (public-client-version-rpc
                        (devnet-smoke-gate-rpc-body
                         public-client-version-response))
                      (public-net-version-rpc
                        (devnet-smoke-gate-rpc-body
                         public-net-version-response))
                      (public-net-listening-rpc
                        (devnet-smoke-gate-rpc-body
                         public-net-listening-response))
                      (public-syncing-rpc
                        (devnet-smoke-gate-rpc-body public-syncing-response))
                      (public-net-peer-count-rpc
                        (devnet-smoke-gate-rpc-body
                         public-net-peer-count-response))
                      (public-accounts-rpc
                        (devnet-smoke-gate-rpc-body public-accounts-response))
                      (public-coinbase-rpc
                        (devnet-smoke-gate-rpc-body public-coinbase-response))
                      (public-mining-rpc
                        (devnet-smoke-gate-rpc-body public-mining-response))
                      (public-hashrate-rpc
                        (devnet-smoke-gate-rpc-body public-hashrate-response))
                      (public-rpc-modules-rpc
                        (devnet-smoke-gate-rpc-body
                         public-rpc-modules-response))
                      (public-rpc-modules
                        (fixture-object-field public-rpc-modules-rpc
                                              "result"))
                      (public-protocol-version-rpc
                        (devnet-smoke-gate-rpc-body
                         public-protocol-version-response))
                      (public-web3-sha3-rpc
                        (devnet-smoke-gate-rpc-body
                         public-web3-sha3-response))
                      (public-gas-price-rpc
                        (devnet-smoke-gate-rpc-body public-gas-price-response))
                      (public-priority-fee-rpc
                        (devnet-smoke-gate-rpc-body
                         public-priority-fee-response))
                      (public-base-fee-rpc
                        (devnet-smoke-gate-rpc-body public-base-fee-response))
                      (public-blob-base-fee-rpc
                        (devnet-smoke-gate-rpc-body
                         public-blob-base-fee-response))
                      (public-fee-history-rpc
                        (devnet-smoke-gate-rpc-body
                         public-fee-history-response))
                      (public-fee-history
                        (fixture-object-field public-fee-history-rpc
                                              "result"))
                      (public-batch-rpc
                        (devnet-smoke-gate-rpc-body public-batch-response))
                      (public-batch-chain-id-rpc (first public-batch-rpc))
                      (public-batch-network-rpc (second public-batch-rpc))
                      (public-batch-client-version-rpc (third public-batch-rpc))
                      (public-engine-namespace-rpc
                        (devnet-smoke-gate-rpc-body
                         public-engine-namespace-response))
                      (public-malformed-json-rpc
                        (devnet-smoke-gate-rpc-body
                         public-malformed-json-response))
                      (new-pending-filter-rpc
                        (devnet-smoke-gate-rpc-body
                         new-pending-filter-response))
                      (pending-filter-changes-rpc
                        (devnet-smoke-gate-rpc-body
                         pending-filter-changes-response))
                      (empty-pending-filter-changes-rpc
                        (devnet-smoke-gate-rpc-body
                         empty-pending-filter-changes-response
                         :preserve-empty-arrays t))
                      (uninstall-pending-filter-rpc
                        (devnet-smoke-gate-rpc-body
                         uninstall-pending-filter-response))
                      (removed-pending-filter-changes-rpc
                        (devnet-smoke-gate-rpc-body
                         removed-pending-filter-changes-response))
                      (send-raw-rpc
                        (devnet-smoke-gate-rpc-body send-raw-response))
                      (send-basefee-rpc
                        (devnet-smoke-gate-rpc-body send-basefee-response))
                      (send-queued-rpc
                        (devnet-smoke-gate-rpc-body send-queued-response))
                      (send-replacement-rpc
                        (devnet-smoke-gate-rpc-body
                         send-replacement-response))
                      (txpool-rejournal-rpc
                        (devnet-smoke-gate-rpc-body
                         txpool-rejournal-response))
                      (raw-pending-rpc
                        (devnet-smoke-gate-rpc-body raw-pending-response))
                      (raw-basefee-rpc
                        (devnet-smoke-gate-rpc-body raw-basefee-response))
                      (raw-queued-rpc
                        (devnet-smoke-gate-rpc-body raw-queued-response))
                      (pending-nonce-rpc
                        (devnet-smoke-gate-rpc-body pending-nonce-response))
                      (pending-block-receipts-rpc
                        (devnet-smoke-gate-rpc-body
                         pending-block-receipts-response))
                      (pending-uncle-count-rpc
                        (devnet-smoke-gate-rpc-body
                         pending-uncle-count-response))
                      (pending-logs-rpc
                        (devnet-smoke-gate-rpc-body
                         pending-logs-response
                         :preserve-empty-arrays t))
                      (txpool-status-rpc
                        (devnet-smoke-gate-rpc-body txpool-status-response))
                      (txpool-content-from-rpc
                        (devnet-smoke-gate-rpc-body
                         txpool-content-from-response))
                      (txpool-inspect-rpc
                        (devnet-smoke-gate-rpc-body txpool-inspect-response))
                      (post-prepared-txpool-content-from-rpc
                        (devnet-smoke-gate-rpc-body
                         post-prepared-txpool-content-from-response))
                      (prepare-replacement-txpool-payload-rpc
                        (devnet-smoke-gate-rpc-body
                         prepare-replacement-txpool-payload-response))
                      (get-replacement-txpool-payload-rpc
                        (devnet-smoke-gate-rpc-body
                         get-replacement-txpool-payload-response))
                      (post-replacement-txpool-content-from-rpc
                        (devnet-smoke-gate-rpc-body
                         post-replacement-txpool-content-from-response))
                      (post-import-transaction-rpc
                        (devnet-smoke-gate-rpc-body
                         post-import-transaction-response))
                      (post-import-receipt-rpc
                        (devnet-smoke-gate-rpc-body
                         post-import-receipt-response))
                      (post-import-raw-rpc
                        (devnet-smoke-gate-rpc-body
                         post-import-raw-response))
                      (post-import-block-rpc
                        (devnet-smoke-gate-rpc-body
                         post-import-block-response))
                      (post-import-txpool-status-rpc
                        (devnet-smoke-gate-rpc-body
                         post-import-txpool-status-response))
                      (post-import-txpool-content-from-rpc
                        (devnet-smoke-gate-rpc-body
                         post-import-txpool-content-from-response))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result"))
                      (client-version-result
                        (first (fixture-object-field
                                client-version-rpc "result")))
                      (transition-configuration-result
                        (fixture-object-field
                         transition-configuration-rpc "result"))
                      (transition-configuration-mismatch-error
                        (fixture-object-field
                         transition-configuration-mismatch-rpc "error"))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus"))
                      (payload-bodies-by-hash-result
                        (fixture-object-field
                         payload-bodies-by-hash-rpc "result"))
                      (payload-bodies-by-range-result
                        (fixture-object-field
                         payload-bodies-by-range-rpc "result"))
                      (payload-body-by-hash
                        (first payload-bodies-by-hash-result))
                      (payload-body-by-range
                        (first payload-bodies-by-range-result))
                      (payload-body-by-hash-transactions
                        (fixture-object-field
                         payload-body-by-hash "transactions"))
                      (payload-body-by-range-transactions
                        (fixture-object-field
                         payload-body-by-range "transactions"))
                      (expected-payload-body-transaction-count
                        (length (block-transactions child-block)))
                      (prepare-payload-result
                        (fixture-object-field prepare-payload-rpc "result"))
                      (prepare-payload-status
                        (fixture-object-field
                         prepare-payload-result
                         "payloadStatus"))
                      (prepared-payload-id
                        (fixture-object-field
                         prepare-payload-result
                         "payloadId"))
                      (get-payload-result
                        (fixture-object-field get-payload-rpc "result"))
                      (get-payload-execution-payload
                        (fixture-object-field
                         get-payload-result
                         "executionPayload"))
                      (get-payload-transactions
                        (fixture-object-field
                         get-payload-execution-payload
                         "transactions"))
                      (prepare-txpool-payload-result
                        (fixture-object-field prepare-txpool-payload-rpc
                                              "result"))
                      (prepare-txpool-payload-status
                        (fixture-object-field
                         prepare-txpool-payload-result
                         "payloadStatus"))
                      (prepared-txpool-payload-id
                        (fixture-object-field
                         prepare-txpool-payload-result
                         "payloadId"))
                      (get-txpool-payload-result
                        (fixture-object-field get-txpool-payload-rpc
                                              "result"))
                      (get-txpool-payload-execution-payload
                        (fixture-object-field
                         get-txpool-payload-result
                         "executionPayload"))
                      (get-txpool-payload-transactions
                        (fixture-object-field
                         get-txpool-payload-execution-payload
                         "transactions"))
                      (txpool-payload-block-hash
                        (fixture-object-field
                         get-txpool-payload-execution-payload
                         "blockHash"))
                      (prepare-replacement-txpool-payload-result
                        (fixture-object-field
                         prepare-replacement-txpool-payload-rpc
                         "result"))
                      (prepare-replacement-txpool-payload-status
                        (fixture-object-field
                         prepare-replacement-txpool-payload-result
                         "payloadStatus"))
                      (prepared-replacement-txpool-payload-id
                        (fixture-object-field
                         prepare-replacement-txpool-payload-result
                         "payloadId"))
                      (get-replacement-txpool-payload-result
                        (fixture-object-field
                         get-replacement-txpool-payload-rpc
                         "result"))
                      (get-replacement-txpool-payload-execution-payload
                        (fixture-object-field
                         get-replacement-txpool-payload-result
                         "executionPayload"))
                      (get-replacement-txpool-payload-transactions
                        (fixture-object-field
                         get-replacement-txpool-payload-execution-payload
                         "transactions"))
                      (import-txpool-payload-result
                        (fixture-object-field import-txpool-payload-rpc
                                              "result"))
                      (forkchoice-txpool-payload-status
                        (fixture-object-field
                         (fixture-object-field
                          forkchoice-txpool-payload-rpc "result")
                         "payloadStatus"))
                      (remote-payload-result
                        (fixture-object-field remote-payload-rpc "result"))
                      (invalid-payload-result
                        (fixture-object-field invalid-payload-rpc "result"))
                      (expected-hash
                        (hash32-to-hex (block-hash child-block)))
                      (expected-remote-block-hash
                        (hash32-to-hex (block-hash remote-block)))
                      (expected-invalid-block-hash
                        (hash32-to-hex (block-hash invalid-block)))
                      (expected-gas-price
                        (quantity-to-hex
                         (or (block-header-base-fee-per-gas
                              (block-header child-block))
                             0)))
                      (expected-next-base-fee
                        (quantity-to-hex
                         (expected-base-fee-per-gas
                          (block-header child-block)
                          :london-parent-p
                          (not (null
                                (block-header-base-fee-per-gas
                                 (block-header child-block)))))))
                      (txpool-status
                        (fixture-object-field txpool-status-rpc "result"))
                      (pending-filter-id
                        (fixture-object-field new-pending-filter-rpc
                                              "result"))
                      (pending-filter-changes
                        (fixture-object-field pending-filter-changes-rpc
                                              "result"))
                      (empty-pending-filter-changes
                        (fixture-object-field
                         empty-pending-filter-changes-rpc
                         "result"))
                      (removed-pending-filter-error
                        (fixture-object-field
                         removed-pending-filter-changes-rpc
                         "error"))
                      (txpool-content-from
                        (fixture-object-field
                         txpool-content-from-rpc "result"))
                      (txpool-content-from-pending
                        (fixture-object-field
                         txpool-content-from "pending"))
                      (txpool-content-from-transaction
                        (fixture-object-field
                         txpool-content-from-pending
                         pending-transaction-nonce-key))
                      (txpool-content-from-queued
                        (fixture-object-field
                         txpool-content-from "queued"))
                      (txpool-content-from-basefee-transaction
                        (fixture-object-field
                         txpool-content-from-queued
                         basefee-transaction-nonce-key))
                      (txpool-content-from-queued-transaction
                        (fixture-object-field
                         txpool-content-from-queued
                         queued-transaction-nonce-key))
                      (txpool-inspect
                        (fixture-object-field txpool-inspect-rpc "result"))
                      (txpool-inspect-pending
                        (fixture-object-field txpool-inspect "pending"))
                      (txpool-inspect-sender
                        (fixture-object-field
                         txpool-inspect-pending
                         pending-transaction-sender-hex))
                      (txpool-inspect-transaction
                        (fixture-object-field
                         txpool-inspect-sender
                         pending-transaction-nonce-key))
                      (txpool-inspect-queued
                        (fixture-object-field txpool-inspect "queued"))
                      (txpool-inspect-queued-sender
                        (fixture-object-field
                         txpool-inspect-queued
                         pending-transaction-sender-hex))
                      (txpool-inspect-basefee-transaction
                        (fixture-object-field
                         txpool-inspect-queued-sender
                         basefee-transaction-nonce-key))
                      (txpool-inspect-queued-transaction
                        (fixture-object-field
                         txpool-inspect-queued-sender
                         queued-transaction-nonce-key))
                      (post-prepared-txpool-content-from
                        (fixture-object-field
                         post-prepared-txpool-content-from-rpc "result"))
                      (post-prepared-txpool-content-from-pending
                        (fixture-object-field
                         post-prepared-txpool-content-from "pending"))
                      (post-prepared-txpool-content-from-transaction
                        (fixture-object-field
                         post-prepared-txpool-content-from-pending
                         pending-transaction-nonce-key))
                      (post-prepared-txpool-content-from-queued
                        (fixture-object-field
                         post-prepared-txpool-content-from "queued"))
                      (post-prepared-txpool-content-from-basefee-transaction
                        (fixture-object-field
                         post-prepared-txpool-content-from-queued
                         basefee-transaction-nonce-key))
                      (post-prepared-txpool-content-from-queued-transaction
                        (fixture-object-field
                         post-prepared-txpool-content-from-queued
                         queued-transaction-nonce-key))
                      (post-replacement-txpool-content-from
                        (fixture-object-field
                         post-replacement-txpool-content-from-rpc "result"))
                      (post-replacement-txpool-content-from-pending
                        (fixture-object-field
                         post-replacement-txpool-content-from "pending"))
                      (post-replacement-txpool-content-from-transaction
                        (fixture-object-field
                         post-replacement-txpool-content-from-pending
                         pending-transaction-nonce-key))
                      (post-replacement-txpool-content-from-queued
                        (fixture-object-field
                         post-replacement-txpool-content-from "queued"))
                      (post-replacement-txpool-content-from-basefee-transaction
                        (fixture-object-field
                         post-replacement-txpool-content-from-queued
                         basefee-transaction-nonce-key))
                      (post-replacement-txpool-content-from-queued-transaction
                        (fixture-object-field
                         post-replacement-txpool-content-from-queued
                         queued-transaction-nonce-key))
                      (post-import-transaction
                        (fixture-object-field
                         post-import-transaction-rpc "result"))
                      (post-import-receipt
                        (fixture-object-field
                         post-import-receipt-rpc "result"))
                      (post-import-raw-transaction
                        (fixture-object-field
                         post-import-raw-rpc "result"))
                      (post-import-block
                        (fixture-object-field
                         post-import-block-rpc "result"))
                      (post-import-block-transactions
                        (fixture-object-field
                         post-import-block "transactions"))
                      (post-import-txpool-status
                        (fixture-object-field
                         post-import-txpool-status-rpc "result"))
                      (post-import-txpool-content-from
                        (fixture-object-field
                         post-import-txpool-content-from-rpc "result"))
                      (post-import-txpool-content-from-pending
                        (fixture-object-field
                         post-import-txpool-content-from "pending"))
                      (post-import-txpool-content-from-selected
                        (fixture-object-field
                         post-import-txpool-content-from-pending
                         pending-transaction-nonce-key))
                      (post-import-txpool-content-from-queued
                        (fixture-object-field
                         post-import-txpool-content-from "queued"))
                      (post-import-txpool-content-from-basefee-transaction
                        (fixture-object-field
                         post-import-txpool-content-from-queued
                         basefee-transaction-nonce-key))
                      (post-import-txpool-content-from-queued-transaction
                        (fixture-object-field
                         post-import-txpool-content-from-queued
                         queued-transaction-nonce-key))
                  (expected-block-number
                    (fixture-object-field payload-case "number"))
                  (expected-prepared-block-number
                    (quantity-to-hex
                     (1+ (block-header-number (block-header child-block)))))
                  (expected-safe-block-number
                    (quantity-to-hex
                     (block-header-number (block-header parent-block))))
                  (expected-safe-block-hash (block-hash parent-block))
                  (expected-finalized-block-number expected-safe-block-number)
                  (expected-finalized-block-hash expected-safe-block-hash)
                      (actual-block-number
                        (fixture-object-field block-number-rpc "result"))
                      (actual-balance
                        (fixture-object-field balance-rpc "result")))
                 (devnet-smoke-gate-require
                  (= +devnet-smoke-gate-engine-connections+
                     (getf summary :engine-connections))
                  "Expected ~D Engine connections, got ~S"
                  +devnet-smoke-gate-engine-connections+
                  (getf summary :engine-connections))
                 (devnet-smoke-gate-require
                  (= +devnet-smoke-gate-public-connections+
                     (getf summary :public-connections))
                  "Expected ~D public RPC connections, got ~S"
                  +devnet-smoke-gate-public-connections+
                  (getf summary :public-connections))
                 (devnet-smoke-gate-require
                  (= 401 (devnet-cli-http-status
                          unauthenticated-engine-response))
                  "Unauthenticated Engine request HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 401 (devnet-cli-http-status
                          invalid-auth-engine-response))
                 "Invalid-token Engine request HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 401 (devnet-cli-http-status
                          duplicate-auth-engine-response))
                  "Duplicate-authorization Engine request HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 404 (devnet-cli-http-status
                          engine-root-wrong-path-response))
                  "Engine default root wrong-path HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status capabilities-response))
                  "engine_exchangeCapabilities HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status client-version-response))
                  "engine_getClientVersionV1 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          transition-configuration-response))
                  "engine_exchangeTransitionConfigurationV1 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          transition-configuration-mismatch-response))
                  "engine_exchangeTransitionConfigurationV1 mismatch HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          engine-public-namespace-response))
                  "Engine public namespace probe HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status new-payload-response))
                  "engine_newPayloadV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status forkchoice-response))
                  "engine_forkchoiceUpdatedV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          payload-bodies-by-hash-response))
                  "engine_getPayloadBodiesByHashV1 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          payload-bodies-by-range-response))
                  "engine_getPayloadBodiesByRangeV1 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status prepare-payload-response))
                  "engine_forkchoiceUpdatedV2 payloadAttributes HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status get-payload-response))
                  "engine_getPayloadV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          prepare-txpool-payload-response))
                  "engine_forkchoiceUpdatedV2 txpool payloadAttributes HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status
                          get-txpool-payload-response))
                  "engine_getPayloadV2 txpool HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          import-txpool-payload-response))
                  "engine_newPayloadV2 txpool prepared payload HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          forkchoice-txpool-payload-response))
                  "engine_forkchoiceUpdatedV2 txpool prepared payload HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status remote-payload-response))
                  "orphan engine_newPayloadV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status invalid-payload-response))
                  "invalid engine_newPayloadV2 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status block-number-response))
                  "eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status balance-response))
                  "eth_getBalance HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status prepared-public-response))
                  "prepared-payload eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status remote-public-response))
                  "remote-block eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status invalid-public-response))
                  "invalid-tipset eth_blockNumber HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-client-version-response))
                  "web3_clientVersion HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-net-version-response))
                  "net_version HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-net-listening-response))
                  "net_listening HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-syncing-response))
                  "eth_syncing HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-net-peer-count-response))
                  "net_peerCount HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-accounts-response))
                  "eth_accounts HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-coinbase-response))
                  "eth_coinbase HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-mining-response))
                  "eth_mining HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status public-hashrate-response))
                  "eth_hashrate HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-rpc-modules-response))
                  "rpc_modules HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-protocol-version-response))
                  "eth_protocolVersion HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-web3-sha3-response))
                  "web3_sha3 HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-gas-price-response))
                  "eth_gasPrice HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-priority-fee-response))
                  "eth_maxPriorityFeePerGas HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-base-fee-response))
                  "eth_baseFee HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-blob-base-fee-response))
                  "eth_blobBaseFee HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-fee-history-response))
                  "eth_feeHistory HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status public-batch-response))
                  "Public JSON-RPC batch HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-engine-namespace-response))
                 "Public Engine namespace probe HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          public-malformed-json-response))
                  "Public malformed JSON probe HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 404 (devnet-cli-http-status
                          public-root-wrong-path-response))
                  "Public default root wrong-path HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          new-pending-filter-response))
                  "eth_newPendingTransactionFilter HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          pending-filter-changes-response))
                  "eth_getFilterChanges HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          empty-pending-filter-changes-response))
                  "drained eth_getFilterChanges HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          uninstall-pending-filter-response))
                  "eth_uninstallFilter HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          removed-pending-filter-changes-response))
                  "removed eth_getFilterChanges HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= -32601
                     (fixture-object-field
                      (fixture-object-field
                       public-engine-namespace-rpc
                       "error")
                      "code"))
                  "Public listener exposed Engine namespace")
                 (devnet-smoke-gate-require
                  (= -32700
                     (fixture-object-field
                      (fixture-object-field
                       public-malformed-json-rpc
                       "error")
                      "code"))
                  "Public listener malformed JSON did not return parse error")
                 (devnet-smoke-gate-require
                  (string= "0x1" pending-filter-id)
                  "eth_newPendingTransactionFilter id mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status send-raw-response))
                  "eth_sendRawTransaction HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status send-basefee-response))
                  "eth_sendRawTransaction basefee HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status send-queued-response))
                  "eth_sendRawTransaction queued HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status send-replacement-response))
                  "eth_sendRawTransaction replacement HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status raw-pending-response))
                  "eth_getRawTransactionByHash pending HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status raw-basefee-response))
                  "eth_getRawTransactionByHash basefee HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status raw-queued-response))
                  "eth_getRawTransactionByHash queued HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status pending-nonce-response))
                  "eth_getTransactionCount pending HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          pending-block-receipts-response))
                  "eth_getBlockReceipts pending HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          pending-uncle-count-response))
                  "eth_getUncleCountByBlockNumber pending HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status pending-logs-response))
                  "eth_getLogs pending HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status txpool-status-response))
                  "txpool_status HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status txpool-content-from-response))
                 "txpool_contentFrom HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status txpool-inspect-response))
                  "txpool_inspect HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status
                          post-prepared-txpool-content-from-response))
                  "post-prepared txpool_contentFrom HTTP status mismatch")
                 (devnet-smoke-gate-require
                 (= 200 (devnet-cli-http-status
                          post-replacement-txpool-content-from-response))
                  "post-replacement txpool_contentFrom HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          post-import-transaction-response))
                  "post-import eth_getTransactionByHash HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          post-import-receipt-response))
                  "post-import eth_getTransactionReceipt HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          post-import-raw-response))
                  "post-import eth_getRawTransactionByHash HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          post-import-block-response))
                  "post-import eth_getBlockByHash HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          post-import-txpool-status-response))
                  "post-import txpool_status HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status
                          post-import-txpool-content-from-response))
                  "post-import txpool_contentFrom HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (member "engine_newPayloadV1"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_newPayloadV1")
                 (devnet-smoke-gate-require
                  (member "engine_forkchoiceUpdatedV1"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_forkchoiceUpdatedV1")
                 (devnet-smoke-gate-require
                  (member "engine_getPayloadV1"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_getPayloadV1")
                 (devnet-smoke-gate-require
                  (member "engine_newPayloadV2"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_newPayloadV2")
                 (devnet-smoke-gate-require
                  (member "engine_forkchoiceUpdatedV2"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_forkchoiceUpdatedV2")
                 (devnet-smoke-gate-require
                  (member "engine_getPayloadV2"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_getPayloadV2")
                 (devnet-smoke-gate-require
                  (member "engine_getPayloadBodiesByHashV1"
                          capabilities-result
                          :test #'string=)
                 "engine_exchangeCapabilities omitted engine_getPayloadBodiesByHashV1")
                 (devnet-smoke-gate-require
                  (member "engine_getPayloadBodiesByRangeV1"
                          capabilities-result
                          :test #'string=)
                  "engine_exchangeCapabilities omitted engine_getPayloadBodiesByRangeV1")
                 (devnet-smoke-gate-require
                  (not (member "engine_newPayloadV3"
                               capabilities-result
                               :test #'string=))
                  "engine_exchangeCapabilities advertised engine_newPayloadV3 without KZG verification")
                 (devnet-smoke-gate-require
                  (not (member "engine_getBlobsV1"
                               capabilities-result
                               :test #'string=))
                  "engine_exchangeCapabilities advertised engine_getBlobsV1 without KZG verification")
                 (devnet-smoke-gate-require
                  (not (member "engine_getBlobsV2"
                               capabilities-result
                               :test #'string=))
                  "engine_exchangeCapabilities advertised engine_getBlobsV2 without KZG verification")
                 (devnet-smoke-gate-require
                  (not (member "engine_getBlobsV3"
                               capabilities-result
                               :test #'string=))
                  "engine_exchangeCapabilities advertised engine_getBlobsV3 without KZG verification")
                 (devnet-smoke-gate-require
                 (not (member "engine_getPayloadBodiesByHashV2"
                               capabilities-result
                               :test #'string=))
                  "engine_exchangeCapabilities advertised engine_getPayloadBodiesByHashV2 without KZG verification")
                 (devnet-smoke-gate-require
                  (not (member "engine_getPayloadBodiesByRangeV2"
                               capabilities-result
                               :test #'string=))
                  "engine_exchangeCapabilities advertised engine_getPayloadBodiesByRangeV2 without KZG verification")
                 (devnet-smoke-gate-require
                  (string= "CL"
                           (fixture-object-field client-version-result "code"))
                  "engine_getClientVersionV1 code mismatch")
                 (devnet-smoke-gate-require
                  (string= "ethereum-lisp"
                           (fixture-object-field client-version-result "name"))
                  "engine_getClientVersionV1 name mismatch")
                 (devnet-smoke-gate-require
                  (string= "0.1.0"
                           (fixture-object-field client-version-result "version"))
                  "engine_getClientVersionV1 version mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x00000000"
                           (fixture-object-field client-version-result "commit"))
                  "engine_getClientVersionV1 commit mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-terminal-total-difficulty
                           (fixture-object-field
                            transition-configuration-result
                            "terminalTotalDifficulty"))
                  "engine_exchangeTransitionConfigurationV1 terminalTotalDifficulty mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-terminal-block-hash
                           (fixture-object-field
                            transition-configuration-result
                            "terminalBlockHash"))
                  "engine_exchangeTransitionConfigurationV1 terminalBlockHash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-terminal-block-number
                           (fixture-object-field
                            transition-configuration-result
                            "terminalBlockNumber"))
                  "engine_exchangeTransitionConfigurationV1 terminalBlockNumber mismatch")
                 (devnet-smoke-gate-require
                  (= -32602
                     (fixture-object-field
                      transition-configuration-mismatch-error
                      "code"))
                  "engine_exchangeTransitionConfigurationV1 mismatch error code mismatch")
                 (devnet-smoke-gate-require
                  (search "terminalTotalDifficulty mismatch"
                          (fixture-object-field
                           transition-configuration-mismatch-error
                           "message"))
                  "engine_exchangeTransitionConfigurationV1 mismatch error message mismatch")
                 (devnet-smoke-gate-require
                  (= -32601
                     (fixture-object-field
                      (fixture-object-field
                       engine-public-namespace-rpc
                       "error")
                      "code"))
                  "Engine listener exposed public namespace")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field new-payload-result "status"))
                  "engine_newPayloadV2 status mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-hash
                           (fixture-object-field new-payload-result
                                                 "latestValidHash"))
                  "latestValidHash mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field forkchoice-status "status"))
                  "engine_forkchoiceUpdatedV2 status mismatch")
                 (devnet-smoke-gate-require
                  (= 1 (length payload-bodies-by-hash-result))
                  "engine_getPayloadBodiesByHashV1 body count mismatch")
                 (devnet-smoke-gate-require
                  (= 1 (length payload-bodies-by-range-result))
                  "engine_getPayloadBodiesByRangeV1 body count mismatch")
                 (devnet-smoke-gate-require
                  (= expected-payload-body-transaction-count
                     (length payload-body-by-hash-transactions))
                  "engine_getPayloadBodiesByHashV1 transaction count mismatch")
                 (devnet-smoke-gate-require
                  (= expected-payload-body-transaction-count
                     (length payload-body-by-range-transactions))
                  "engine_getPayloadBodiesByRangeV1 transaction count mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field prepare-payload-status
                                                 "status"))
                  "engine_forkchoiceUpdatedV2 payloadAttributes status mismatch")
                 (devnet-smoke-gate-require
                  (and (stringp prepared-payload-id)
                       (= 18 (length prepared-payload-id)))
                  "engine_forkchoiceUpdatedV2 did not return an 8-byte payloadId")
                 (devnet-smoke-gate-require
                  (not (fixture-object-field get-payload-rpc "error"))
                  "engine_getPayloadV2 returned an error")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-payload-id prepared-payload-id)
                  "engine_forkchoiceUpdatedV2 payloadId mismatch")
                 (devnet-smoke-gate-require
                  (string= (hash32-to-hex (block-hash child-block))
                           (fixture-object-field
                            get-payload-execution-payload
                            "parentHash"))
                  "engine_getPayloadV2 parentHash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-block-number
                           (fixture-object-field
                            get-payload-execution-payload
                            "blockNumber"))
                  "engine_getPayloadV2 blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (listp get-payload-transactions)
                  "engine_getPayloadV2 transactions must be a JSON array")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field
                            prepare-txpool-payload-status
                            "status"))
                  "engine_forkchoiceUpdatedV2 txpool payloadAttributes status mismatch")
                 (devnet-smoke-gate-require
                  (and (stringp prepared-txpool-payload-id)
                       (= 18 (length prepared-txpool-payload-id)))
                  "engine_forkchoiceUpdatedV2 txpool did not return an 8-byte payloadId")
                 (devnet-smoke-gate-require
                  (not (fixture-object-field get-txpool-payload-rpc "error"))
                  "engine_getPayloadV2 txpool returned an error: ~S"
                  (fixture-object-field get-txpool-payload-rpc "error"))
                 (devnet-smoke-gate-require
                  (string= (hash32-to-hex (block-hash child-block))
                           (fixture-object-field
                            get-txpool-payload-execution-payload
                            "parentHash"))
                  "engine_getPayloadV2 txpool parentHash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-block-number
                           (fixture-object-field
                            get-txpool-payload-execution-payload
                            "blockNumber"))
                  "engine_getPayloadV2 txpool blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (listp get-txpool-payload-transactions)
                  "engine_getPayloadV2 txpool transactions must be a JSON array")
                 (devnet-smoke-gate-require
                  (= 1 (length get-txpool-payload-transactions))
                  "engine_getPayloadV2 txpool should select exactly one executable transaction")
                 (devnet-smoke-gate-require
                  (member pending-transaction-raw
                          get-txpool-payload-transactions
                          :test #'string=)
                  "engine_getPayloadV2 txpool omitted executable pending transaction")
                 (devnet-smoke-gate-require
                  (not (member basefee-transaction-raw
                               get-txpool-payload-transactions
                               :test #'string=))
                  "engine_getPayloadV2 txpool selected underpriced basefee transaction")
                 (devnet-smoke-gate-require
                 (not (member queued-transaction-raw
                               get-txpool-payload-transactions
                               :test #'string=))
                  "engine_getPayloadV2 txpool selected nonce-gapped queued transaction")
                 (devnet-smoke-gate-require
                  (string= replacement-transaction-hash-hex
                           (fixture-object-field
                            send-replacement-rpc "result"))
                  "eth_sendRawTransaction replacement hash mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field
                            prepare-replacement-txpool-payload-status
                            "status"))
                  "replacement engine_forkchoiceUpdatedV2 txpool payloadAttributes status mismatch")
                 (devnet-smoke-gate-require
                  (and (stringp prepared-replacement-txpool-payload-id)
                       (= 18 (length prepared-replacement-txpool-payload-id)))
                  "replacement engine_forkchoiceUpdatedV2 txpool did not return an 8-byte payloadId")
                 (devnet-smoke-gate-require
                  (not (string= prepared-txpool-payload-id
                                prepared-replacement-txpool-payload-id))
                  "replacement txpool payload id did not change")
                 (devnet-smoke-gate-require
                  (not (fixture-object-field
                        get-replacement-txpool-payload-rpc "error"))
                  "replacement engine_getPayloadV2 txpool returned an error: ~S"
                  (fixture-object-field
                   get-replacement-txpool-payload-rpc "error"))
                 (devnet-smoke-gate-require
                  (string= (hash32-to-hex (block-hash child-block))
                           (fixture-object-field
                            get-replacement-txpool-payload-execution-payload
                            "parentHash"))
                  "replacement engine_getPayloadV2 txpool parentHash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-block-number
                           (fixture-object-field
                            get-replacement-txpool-payload-execution-payload
                            "blockNumber"))
                  "replacement engine_getPayloadV2 txpool blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (listp get-replacement-txpool-payload-transactions)
                  "replacement engine_getPayloadV2 txpool transactions must be a JSON array")
                 (devnet-smoke-gate-require
                  (= 1 (length get-replacement-txpool-payload-transactions))
                  "replacement engine_getPayloadV2 txpool should select exactly one executable transaction")
                 (devnet-smoke-gate-require
                  (member replacement-transaction-raw
                          get-replacement-txpool-payload-transactions
                          :test #'string=)
                  "replacement engine_getPayloadV2 txpool omitted replacement transaction")
                 (devnet-smoke-gate-require
                  (not (member pending-transaction-raw
                               get-replacement-txpool-payload-transactions
                               :test #'string=))
                  "replacement engine_getPayloadV2 txpool retained original transaction")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field
                            import-txpool-payload-result
                            "status"))
                  "engine_newPayloadV2 txpool prepared payload status mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-txpool-block-hash
                           (fixture-object-field
                            import-txpool-payload-result
                            "latestValidHash"))
                  "engine_newPayloadV2 txpool latestValidHash mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-valid+
                           (fixture-object-field
                            forkchoice-txpool-payload-status
                            "status"))
                  "engine_forkchoiceUpdatedV2 txpool prepared payload status mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-transaction-hash-hex
                           (fixture-object-field
                            post-import-transaction
                            "hash"))
                  "post-import eth_getTransactionByHash hash mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-txpool-block-hash
                           (fixture-object-field
                            post-import-transaction
                            "blockHash"))
                  "post-import eth_getTransactionByHash blockHash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-block-number
                           (fixture-object-field
                            post-import-transaction
                            "blockNumber"))
                  "post-import eth_getTransactionByHash blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x0"
                           (fixture-object-field
                            post-import-transaction
                            "transactionIndex"))
                  "post-import eth_getTransactionByHash transactionIndex mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-transaction-hash-hex
                           (fixture-object-field
                            post-import-receipt
                            "transactionHash"))
                  "post-import eth_getTransactionReceipt hash mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-txpool-block-hash
                           (fixture-object-field
                            post-import-receipt
                            "blockHash"))
                  "post-import eth_getTransactionReceipt blockHash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-block-number
                           (fixture-object-field
                            post-import-receipt
                            "blockNumber"))
                  "post-import eth_getTransactionReceipt blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-transaction-raw
                           post-import-raw-transaction)
                  "post-import eth_getRawTransactionByHash raw mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-txpool-block-hash
                           (fixture-object-field post-import-block "hash"))
                  "post-import eth_getBlockByHash hash mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-prepared-block-number
                           (fixture-object-field post-import-block "number"))
                  "post-import eth_getBlockByHash number mismatch")
                 (devnet-smoke-gate-require
                  (= 1 (length post-import-block-transactions))
                  "post-import eth_getBlockByHash transaction count mismatch")
                 (devnet-smoke-gate-require
                  (string= replacement-transaction-hash-hex
                           (first post-import-block-transactions))
                  "post-import eth_getBlockByHash transaction hash mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x0"
                           (fixture-object-field
                            post-import-txpool-status
                            "pending"))
                  "post-import txpool_status pending count mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x2"
                           (fixture-object-field
                            post-import-txpool-status
                            "queued"))
                  "post-import txpool_status queued count mismatch")
                 (devnet-smoke-gate-require
                  (null post-import-txpool-content-from-selected)
                  "post-import txpool_contentFrom still exposes mined pending transaction")
                 (devnet-smoke-gate-require
                  (string= replacement-transaction-hash-hex
                           (fixture-object-field
                            post-replacement-txpool-content-from-transaction
                            "hash"))
                  "post-replacement txpool_contentFrom hash mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-hash-hex
                           (fixture-object-field
                            post-import-txpool-content-from-basefee-transaction
                            "hash"))
                  "post-import txpool_contentFrom basefee hash mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-hash-hex
                           (fixture-object-field
                            post-import-txpool-content-from-queued-transaction
                            "hash"))
                  "post-import txpool_contentFrom queued hash mismatch")
                 (devnet-smoke-gate-require
                  (string= +payload-status-syncing+
                           (fixture-object-field remote-payload-result
                                                 "status"))
                  "orphan engine_newPayloadV2 status mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field remote-payload-result
                                              "latestValidHash"))
                  "orphan engine_newPayloadV2 should not report latestValidHash")
                 (devnet-smoke-gate-require
                  (ethereum-lisp.chain-store:engine-payload-store-remote-block
                   store (block-hash remote-block))
                  "orphan engine_newPayloadV2 did not populate remote-block cache")
                 (devnet-smoke-gate-require
                  (string= +payload-status-invalid+
                           (fixture-object-field invalid-payload-result
                                                 "status"))
                  "invalid engine_newPayloadV2 status mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-hash
                           (fixture-object-field invalid-payload-result
                                                 "latestValidHash"))
                  "invalid engine_newPayloadV2 latestValidHash mismatch")
                 (devnet-smoke-gate-require
                  (string= "Timestamp is not greater than parent timestamp"
                           (fixture-object-field invalid-payload-result
                                                 "validationError"))
                  "invalid engine_newPayloadV2 validation error mismatch")
                 (devnet-smoke-gate-require
                  (ethereum-lisp.chain-store:engine-payload-store-invalid-block
                   store (block-hash invalid-block))
                  "invalid engine_newPayloadV2 did not populate invalid-tipset cache")
                 (devnet-smoke-gate-require
                  (string= expected-block-number actual-block-number)
                  "eth_blockNumber mismatch: expected ~A got ~A"
                  expected-block-number
                  actual-block-number)
                 (devnet-smoke-gate-require
                  (string= expected-block-number
                           (fixture-object-field prepared-public-rpc "result"))
                  "prepared-payload eth_blockNumber mismatch")
                 (devnet-smoke-gate-require
                 (string= expected-block-number
                           (fixture-object-field remote-public-rpc "result"))
                  "remote-block eth_blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-block-number
                           (fixture-object-field invalid-public-rpc "result"))
                  "invalid-tipset eth_blockNumber mismatch")
                 (devnet-smoke-gate-require
                  (search "ethereum-lisp"
                          (fixture-object-field public-client-version-rpc
                                                "result"))
                  "web3_clientVersion did not expose ethereum-lisp")
                 (devnet-smoke-gate-require
                  (string= (write-to-string
                             (ethereum-lisp.cli::devnet-node-network-id node)
                             :base 10)
                           (fixture-object-field public-net-version-rpc
                                                 "result"))
                  "net_version mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field public-net-listening-rpc
                                              "result"))
                  "net_listening mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field public-syncing-rpc "result"))
                  "eth_syncing mismatch")
                 (devnet-smoke-gate-require
                  (string= (quantity-to-hex 0)
                           (fixture-object-field public-net-peer-count-rpc
                                                 "result"))
                  "net_peerCount mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field public-accounts-rpc "result"))
                  "eth_accounts mismatch")
                 (devnet-smoke-gate-require
                  (string= (address-to-hex (zero-address))
                           (fixture-object-field public-coinbase-rpc
                                                 "result"))
                  "eth_coinbase mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field public-mining-rpc "result"))
                  "eth_mining mismatch")
                 (devnet-smoke-gate-require
                  (string= (quantity-to-hex 0)
                           (fixture-object-field public-hashrate-rpc
                                                 "result"))
                  "eth_hashrate mismatch")
                 (devnet-smoke-gate-require
                  (string= "1.0"
                           (fixture-object-field public-rpc-modules "eth"))
                  "rpc_modules eth module mismatch")
                 (devnet-smoke-gate-require
                  (string= "1.0"
                           (fixture-object-field public-rpc-modules "net"))
                  "rpc_modules net module mismatch")
                 (devnet-smoke-gate-require
                  (string= "1.0"
                           (fixture-object-field public-rpc-modules "rpc"))
                  "rpc_modules rpc module mismatch")
                 (devnet-smoke-gate-require
                  (string= "1.0"
                           (fixture-object-field public-rpc-modules "txpool"))
                  "rpc_modules txpool module mismatch")
                 (devnet-smoke-gate-require
                 (string= "1.0"
                          (fixture-object-field public-rpc-modules "web3"))
                  "rpc_modules web3 module mismatch")
                 (devnet-smoke-gate-require
                  (string= (quantity-to-hex
                            ethereum-lisp.engine-payloads:+eth-protocol-version+)
                           (fixture-object-field
                            public-protocol-version-rpc
                            "result"))
                  "eth_protocolVersion mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x1c8aff950685c2ed4bc3174f3472287b56d9517b9c948127319a09a7a36deac8"
                           (fixture-object-field public-web3-sha3-rpc
                                                 "result"))
                  "web3_sha3 mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-gas-price
                           (fixture-object-field public-gas-price-rpc
                                                 "result"))
                  "eth_gasPrice mismatch")
                 (devnet-smoke-gate-require
                  (string= (quantity-to-hex 0)
                           (fixture-object-field public-priority-fee-rpc
                                                 "result"))
                  "eth_maxPriorityFeePerGas mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-next-base-fee
                           (fixture-object-field public-base-fee-rpc
                                                 "result"))
                  "eth_baseFee mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field public-blob-base-fee-rpc
                                              "result"))
                  "eth_blobBaseFee should be null before Cancun blob data")
                 (devnet-smoke-gate-require
                  (string= expected-block-number
                           (fixture-object-field public-fee-history
                                                 "oldestBlock"))
                  "eth_feeHistory oldestBlock mismatch")
                 (let ((base-fees
                         (fixture-object-field public-fee-history
                                               "baseFeePerGas"))
                       (gas-ratios
                         (fixture-object-field public-fee-history
                                               "gasUsedRatio")))
                   (devnet-smoke-gate-require
                    (= 2 (length base-fees))
                    "eth_feeHistory baseFeePerGas length mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-gas-price (first base-fees))
                    "eth_feeHistory base fee mismatch")
                   (devnet-smoke-gate-require
                    (string= expected-next-base-fee (second base-fees))
                    "eth_feeHistory next base fee mismatch")
                   (devnet-smoke-gate-require
                    (= 1 (length gas-ratios))
                    "eth_feeHistory gasUsedRatio length mismatch")
                   (devnet-smoke-gate-require
                    (realp (first gas-ratios))
                    "eth_feeHistory gasUsedRatio must be numeric"))
                 (devnet-smoke-gate-require
                  (= 3 (length public-batch-rpc))
                  "Public JSON-RPC batch response count mismatch")
                 (devnet-smoke-gate-require
                  (string= (quantity-to-hex
                             (chain-config-chain-id config))
                           (fixture-object-field
                            public-batch-chain-id-rpc
                            "result"))
                  "Public batch eth_chainId mismatch")
                 (devnet-smoke-gate-require
                  (string= (write-to-string
                             (ethereum-lisp.cli::devnet-node-network-id node)
                             :base 10)
                           (fixture-object-field
                            public-batch-network-rpc
                            "result"))
                  "Public batch net_version mismatch")
                 (devnet-smoke-gate-require
                  (search "ethereum-lisp"
                          (fixture-object-field
                           public-batch-client-version-rpc
                           "result"))
                  "Public batch web3_clientVersion mismatch")
                 (devnet-smoke-gate-require
                 (string= pending-transaction-hash-hex
                           (fixture-object-field send-raw-rpc "result"))
                  "eth_sendRawTransaction hash mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-hash-hex
                           (fixture-object-field send-basefee-rpc "result"))
                  "eth_sendRawTransaction basefee hash mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-hash-hex
                           (fixture-object-field send-queued-rpc "result"))
                  "eth_sendRawTransaction queued hash mismatch")
                 (devnet-smoke-gate-require
                  (= 200 (devnet-cli-http-status txpool-rejournal-response))
                  "txpool rejournal wait request HTTP status mismatch")
                 (devnet-smoke-gate-require
                  (string= actual-block-number
                           (fixture-object-field
                            txpool-rejournal-rpc "result"))
                  "txpool rejournal wait request block number mismatch")
                 (devnet-smoke-gate-require
                  txpool-rejournal-report
                  "txpool rejournal did not report the expected record")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-hash-hex
                           (getf txpool-rejournal-report
                                 :transaction-hash))
                  "txpool rejournal transaction hash mismatch")
                 (devnet-smoke-gate-require
                  (eq :pending (getf txpool-rejournal-report :subpool))
                  "txpool rejournal transaction subpool mismatch")
                 (devnet-smoke-gate-require
                  (= 1 (length pending-filter-changes))
                  "eth_getFilterChanges pending transaction count mismatch")
                 (devnet-smoke-gate-require
                 (string= pending-transaction-hash-hex
                           (first pending-filter-changes))
                  "eth_getFilterChanges pending transaction hash mismatch")
                 (devnet-smoke-gate-require
                  (devnet-smoke-gate-empty-json-array-p
                   empty-pending-filter-changes)
                  "drained eth_getFilterChanges should be empty")
                 (devnet-smoke-gate-require
                  (member (fixture-object-field
                           uninstall-pending-filter-rpc
                           "result")
                          '(t :true))
                  "eth_uninstallFilter result mismatch")
                 (devnet-smoke-gate-require
                  (= -32602
                     (fixture-object-field
                      removed-pending-filter-error
                      "code"))
                  "removed eth_getFilterChanges error code mismatch")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-raw
                           (fixture-object-field raw-pending-rpc "result"))
                  "eth_getRawTransactionByHash pending raw mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-raw
                           (fixture-object-field raw-basefee-rpc "result"))
                  "eth_getRawTransactionByHash basefee raw mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-raw
                           (fixture-object-field raw-queued-rpc "result"))
                  "eth_getRawTransactionByHash queued raw mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-pending-sender-nonce
                           (fixture-object-field pending-nonce-rpc "result"))
                  "eth_getTransactionCount pending nonce mismatch")
                 (devnet-smoke-gate-require
                  (null (fixture-object-field
                         pending-block-receipts-rpc "result"))
                  "eth_getBlockReceipts pending should be null")
                 (devnet-smoke-gate-require
                  (string= "0x0"
                           (fixture-object-field
                            pending-uncle-count-rpc "result"))
                  "eth_getUncleCountByBlockNumber pending mismatch")
                 (devnet-smoke-gate-require
                  (devnet-smoke-gate-empty-json-array-p
                   (fixture-object-field pending-logs-rpc "result"))
                  "eth_getLogs pending should be empty")
                 (devnet-smoke-gate-require
                  (string= "0x1"
                           (fixture-object-field txpool-status "pending"))
                  "txpool_status pending count mismatch")
                 (devnet-smoke-gate-require
                  (string= "0x2"
                           (fixture-object-field txpool-status "queued"))
                  "txpool_status queued count mismatch")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-hash-hex
                           (fixture-object-field
                            txpool-content-from-transaction "hash"))
                  "txpool_contentFrom pending hash mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-hash-hex
                           (fixture-object-field
                            txpool-content-from-basefee-transaction "hash"))
                  "txpool_contentFrom basefee hash mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-hash-hex
                           (fixture-object-field
                            txpool-content-from-queued-transaction "hash"))
                  "txpool_contentFrom queued hash mismatch")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-hash-hex
                           (fixture-object-field
                            post-prepared-txpool-content-from-transaction
                            "hash"))
                  "post-prepared txpool_contentFrom pending hash mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-hash-hex
                           (fixture-object-field
                            post-prepared-txpool-content-from-basefee-transaction
                            "hash"))
                  "post-prepared txpool_contentFrom basefee hash mismatch")
                 (devnet-smoke-gate-require
                  (string= queued-transaction-hash-hex
                           (fixture-object-field
                            post-prepared-txpool-content-from-queued-transaction
                            "hash"))
                  "post-prepared txpool_contentFrom queued hash mismatch")
                 (devnet-smoke-gate-require
                  (string= pending-transaction-summary
                           txpool-inspect-transaction)
                  "txpool_inspect pending summary mismatch")
                 (devnet-smoke-gate-require
                  (string= basefee-transaction-summary
                           txpool-inspect-basefee-transaction)
                  "txpool_inspect basefee summary mismatch")
                 (devnet-smoke-gate-require
                 (string= queued-transaction-summary
                          txpool-inspect-queued-transaction)
                  "txpool_inspect queued summary mismatch")
                 (devnet-smoke-gate-require
                  (string= expected-balance actual-balance)
                  "eth_getBalance mismatch: expected ~A got ~A"
                  expected-balance
                  actual-balance)
                 (when database-file
                   (ethereum-lisp.cli::devnet-node-export-database
                    node
                    :state-prune-before state-prune-before))
                 (let ((database-summary
                         (and database-file
                              (devnet-smoke-gate-verify-database
                               database-file
                               expected-block-number
                               balance-targets
                               sender-address
                               expected-sender-nonce
                               code-address
                               expected-code
                               storage-address
                               storage-key
                               expected-storage
                               transaction-checks
                               log-targets
                               (block-hash child-block)
                               expected-safe-block-number
                               expected-safe-block-hash
                               expected-finalized-block-number
                               expected-finalized-block-hash
                               config
                               :state-prune-before state-prune-before
                               :pruned-state-hash expected-safe-block-hash
                               :expected-head-block-number
                               expected-prepared-block-number
                               :checkpoint-balance-targets
                               checkpoint-balance-targets
                               :prepared-payload-id prepared-payload-id
                               :prepared-payload-parent-hash
                               (block-hash child-block)
                               :prepared-payload-block-number
                               expected-prepared-block-number
                               :remote-payload remote-payload
                               :remote-block remote-block
                               :invalid-block invalid-block
                               :invalid-descendant-payload
                               invalid-descendant-payload
                               :txpool-transactions txpool-transactions
                               :selected-txpool-transaction
                               replacement-transaction
                               :side-payload side-payload
                               :side-block side-block
                               :child-block child-block)))
                       (public-api-allowlist-summary
                         (devnet-smoke-gate-verify-public-api-allowlist))
                       (public-cors-summary
                         (devnet-smoke-gate-verify-public-cors))
                       (engine-cors-summary
                         (devnet-smoke-gate-verify-engine-cors))
                       (http-shaping-summary
                         (devnet-smoke-gate-verify-http-shaping))
                       (vhost-summary
                         (devnet-smoke-gate-verify-vhosts))
                       (rpc-prefix-summary
                         (devnet-smoke-gate-verify-rpc-prefixes))
                       (dev-period-summary
                         (devnet-smoke-gate-verify-dev-period-mining
                          case-name
                          :terminal-total-difficulty
                          terminal-total-difficulty
                          :terminal-total-difficulty-passed-p
                          terminal-total-difficulty-passed-p
                          :terminal-block-hash terminal-block-hash
                          :terminal-block-number terminal-block-number)))
                 (devnet-smoke-gate-add-run-metadata
                  (list
                  (cons "status" "ok")
                  (cons "mode" "devnet-listener-boundary")
                  (cons "fixtureCase" case-name)
                  (cons "chainId"
                        (quantity-to-hex
                         (chain-config-chain-id config)))
                  (cons "engineConnections"
                        (getf summary :engine-connections))
                  (cons "publicConnections"
                        (getf summary :public-connections))
                  (cons "totalConnections"
                        (getf summary :total-connections))
                  (cons "connectionContract"
                        (devnet-smoke-gate-connection-contract))
                  (cons "publicApiAllowlist"
                        (getf public-api-allowlist-summary
                              :allowed-modules))
                  (cons "publicApiAllowlistReportedModules"
                        (getf public-api-allowlist-summary
                              :reported-modules))
                  (cons "publicApiAllowlistTelemetryModules"
                        (getf public-api-allowlist-summary
                              :telemetry-modules))
                  (cons "publicApiAllowlistEngineConnections"
                        (getf public-api-allowlist-summary
                              :engine-connections))
                  (cons "publicApiAllowlistPublicConnections"
                        (getf public-api-allowlist-summary
                              :public-connections))
                  (cons "publicApiAllowlistTotalConnections"
                        (getf public-api-allowlist-summary
                              :total-connections))
                  (cons "publicApiAllowlistChainId"
                        (getf public-api-allowlist-summary
                              :chain-id))
                  (cons "publicApiAllowlistNetworkVersion"
                        (getf public-api-allowlist-summary
                              :network-version))
                  (cons "publicApiBlockedWeb3ErrorCode"
                        (getf public-api-allowlist-summary
                              :web3-error-code))
                  (cons "publicApiBlockedTxpoolErrorCode"
                        (getf public-api-allowlist-summary
                              :txpool-error-code))
                  (cons "publicApiBlockedEngineErrorCode"
                        (getf public-api-allowlist-summary
                              :engine-error-code))
                  (cons "publicCorsOrigins"
                        (getf public-cors-summary :origins))
                  (cons "publicCorsReportedOrigins"
                        (getf public-cors-summary :reported-origins))
                  (cons "publicCorsTelemetryOrigins"
                        (getf public-cors-summary :telemetry-origins))
                  (cons "publicCorsPreflightStatus"
                        (getf public-cors-summary :preflight-status))
                  (cons "publicCorsRpcStatus"
                        (getf public-cors-summary :post-status))
                  (cons "publicCorsBlockedStatus"
                        (getf public-cors-summary :blocked-status))
                  (cons "publicCorsEngineConnections"
                        (getf public-cors-summary :engine-connections))
                  (cons "publicCorsPublicConnections"
                        (getf public-cors-summary :public-connections))
                  (cons "publicCorsTotalConnections"
                        (getf public-cors-summary :total-connections))
                  (cons "engineCorsOrigins"
                        (getf engine-cors-summary :origins))
                  (cons "engineCorsReportedOrigins"
                        (getf engine-cors-summary :reported-origins))
                  (cons "engineCorsTelemetryOrigins"
                        (getf engine-cors-summary :telemetry-origins))
                  (cons "engineCorsPreflightStatus"
                        (getf engine-cors-summary :preflight-status))
                  (cons "engineCorsRpcStatus"
                        (getf engine-cors-summary :post-status))
                  (cons "engineCorsBlockedStatus"
                        (getf engine-cors-summary :blocked-status))
                  (cons "engineCorsEngineConnections"
                        (getf engine-cors-summary :engine-connections))
                  (cons "engineCorsPublicConnections"
                        (getf engine-cors-summary :public-connections))
                  (cons "engineCorsTotalConnections"
                        (getf engine-cors-summary :total-connections))
                  (cons "engineHttpMethodStatus"
                        (getf http-shaping-summary :engine-method-status))
                  (cons "engineHttpContentTypeStatus"
                        (getf http-shaping-summary
                              :engine-content-type-status))
                  (cons "publicHttpMethodStatus"
                        (getf http-shaping-summary :public-method-status))
                  (cons "publicHttpContentTypeStatus"
                        (getf http-shaping-summary
                              :public-content-type-status))
                  (cons "httpShapingEngineConnections"
                        (getf http-shaping-summary :engine-connections))
                  (cons "httpShapingPublicConnections"
                        (getf http-shaping-summary :public-connections))
                  (cons "httpShapingTotalConnections"
                        (getf http-shaping-summary :total-connections))
                  (cons "engineVhosts"
                        (getf vhost-summary :engine-vhosts))
                  (cons "publicVhosts"
                        (getf vhost-summary :public-vhosts))
                  (cons "engineVhostsReported"
                        (getf vhost-summary :reported-engine-vhosts))
                  (cons "publicVhostsReported"
                        (getf vhost-summary :reported-public-vhosts))
                  (cons "engineVhostsTelemetry"
                        (getf vhost-summary :telemetry-engine-vhosts))
                  (cons "publicVhostsTelemetry"
                        (getf vhost-summary :telemetry-public-vhosts))
                  (cons "engineVhostAllowedStatus"
                        (getf vhost-summary :engine-allowed-status))
                  (cons "engineVhostBlockedStatus"
                        (getf vhost-summary :engine-blocked-status))
                  (cons "publicVhostAllowedStatus"
                        (getf vhost-summary :public-allowed-status))
                  (cons "publicVhostBlockedStatus"
                        (getf vhost-summary :public-blocked-status))
                  (cons "vhostEngineConnections"
                        (getf vhost-summary :engine-connections))
                  (cons "vhostPublicConnections"
                        (getf vhost-summary :public-connections))
                  (cons "vhostTotalConnections"
                        (getf vhost-summary :total-connections))
                  (cons "engineRpcPrefix"
                        (getf rpc-prefix-summary :engine-prefix))
                  (cons "publicRpcPrefix"
                        (getf rpc-prefix-summary :public-prefix))
                  (cons "engineRpcPrefixReported"
                        (getf rpc-prefix-summary
                              :reported-engine-prefix))
                  (cons "publicRpcPrefixReported"
                        (getf rpc-prefix-summary
                              :reported-public-prefix))
                  (cons "engineRpcPrefixTelemetry"
                        (getf rpc-prefix-summary
                              :telemetry-engine-prefix))
                  (cons "publicRpcPrefixTelemetry"
                        (getf rpc-prefix-summary
                              :telemetry-public-prefix))
                  (cons "engineRpcPrefixStatus"
                        (getf rpc-prefix-summary :engine-status))
                  (cons "engineRpcPrefixBlockedStatus"
                        (getf rpc-prefix-summary
                              :engine-blocked-status))
                  (cons "publicRpcPrefixStatus"
                        (getf rpc-prefix-summary :public-status))
                  (cons "publicRpcPrefixBlockedStatus"
                        (getf rpc-prefix-summary
                              :public-blocked-status))
                  (cons "rpcPrefixEngineConnections"
                        (getf rpc-prefix-summary :engine-connections))
                  (cons "rpcPrefixPublicConnections"
                        (getf rpc-prefix-summary :public-connections))
                  (cons "rpcPrefixTotalConnections"
                        (getf rpc-prefix-summary :total-connections))
                  (cons "engineUnauthenticatedStatus"
                        (devnet-cli-http-status
                         unauthenticated-engine-response))
                  (cons "engineInvalidAuthStatus"
                        (devnet-cli-http-status
                         invalid-auth-engine-response))
                  (cons "engineDuplicateAuthStatus"
                        (devnet-cli-http-status
                         duplicate-auth-engine-response))
                  (cons "engineRootWrongPathStatus"
                        (devnet-cli-http-status
                         engine-root-wrong-path-response))
                  (cons "engineCapabilityCount"
                        (length capabilities-result))
                  (cons "engineCapabilityHasNewPayloadV1"
                        (if (member "engine_newPayloadV1"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasForkchoiceUpdatedV1"
                        (if (member "engine_forkchoiceUpdatedV1"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasGetPayloadV1"
                        (if (member "engine_getPayloadV1"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasNewPayloadV2"
                        (if (member "engine_newPayloadV2"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasForkchoiceUpdatedV2"
                        (if (member "engine_forkchoiceUpdatedV2"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasGetPayloadV2"
                        (if (member "engine_getPayloadV2"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasNewPayloadV3"
                        (if (member "engine_newPayloadV3"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasGetBlobsV1"
                        (if (member "engine_getBlobsV1"
                                    capabilities-result
                                    :test #'string=)
                            t
                            :false))
                  (cons "engineCapabilityHasPayloadBodiesV2"
                        (if (or (member "engine_getPayloadBodiesByHashV2"
                                        capabilities-result
                                        :test #'string=)
                                (member "engine_getPayloadBodiesByRangeV2"
                                        capabilities-result
                                        :test #'string=))
                            t
                            :false))
                  (cons "engineClientVersionCode"
                        (fixture-object-field client-version-result "code"))
                  (cons "engineClientVersionName"
                        (fixture-object-field client-version-result "name"))
                  (cons "engineClientVersionVersion"
                        (fixture-object-field client-version-result "version"))
                  (cons "engineClientVersionCommit"
                        (fixture-object-field client-version-result "commit"))
                  (cons "engineTransitionTerminalTotalDifficulty"
                        (fixture-object-field
                         transition-configuration-result
                         "terminalTotalDifficulty"))
                  (cons "engineTransitionTerminalBlockHash"
                        (fixture-object-field
                         transition-configuration-result
                         "terminalBlockHash"))
                  (cons "engineTransitionTerminalBlockNumber"
                        (fixture-object-field
                         transition-configuration-result
                         "terminalBlockNumber"))
                  (cons "engineTransitionMismatchErrorCode"
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "code"))
                  (cons "engineTransitionMismatchErrorMessage"
                        (fixture-object-field
                         transition-configuration-mismatch-error
                         "message"))
                  (cons "enginePublicNamespaceErrorCode"
                        (fixture-object-field
                         (fixture-object-field
                          engine-public-namespace-rpc
                          "error")
                         "code"))
                  (cons "publicEngineNamespaceErrorCode"
                        (fixture-object-field
                         (fixture-object-field
                          public-engine-namespace-rpc
                          "error")
                         "code"))
                  (cons "publicMalformedJsonErrorCode"
                        (fixture-object-field
                         (fixture-object-field
                          public-malformed-json-rpc
                          "error")
                         "code"))
                  (cons "publicRootWrongPathStatus"
                        (devnet-cli-http-status
                         public-root-wrong-path-response))
                  (cons "publicClientVersion"
                        (fixture-object-field public-client-version-rpc
                                              "result"))
                  (cons "publicNetVersion"
                        (fixture-object-field public-net-version-rpc
                                              "result"))
                  (cons "publicNetListening"
                        (if (fixture-object-field public-net-listening-rpc
                                                  "result")
                            t
                            :false))
                  (cons "publicSyncing"
                        (if (fixture-object-field public-syncing-rpc "result")
                            t
                            :false))
                  (cons "publicNetPeerCount"
                        (fixture-object-field public-net-peer-count-rpc
                                              "result"))
                  (cons "publicAccountCount"
                        (length (fixture-object-field public-accounts-rpc
                                                      "result")))
                  (cons "publicCoinbase"
                        (fixture-object-field public-coinbase-rpc "result"))
                  (cons "publicMining"
                        (if (fixture-object-field public-mining-rpc "result")
                            t
                            :false))
                  (cons "publicHashrate"
                        (fixture-object-field public-hashrate-rpc "result"))
                  (cons "publicRpcModules" public-rpc-modules)
                  (cons "publicProtocolVersion"
                        (fixture-object-field public-protocol-version-rpc
                                              "result"))
                  (cons "publicWeb3Sha3"
                        (fixture-object-field public-web3-sha3-rpc "result"))
                  (cons "publicGasPrice"
                        (fixture-object-field public-gas-price-rpc "result"))
                  (cons "publicMaxPriorityFeePerGas"
                        (fixture-object-field public-priority-fee-rpc
                                              "result"))
                  (cons "publicBaseFee"
                        (fixture-object-field public-base-fee-rpc "result"))
                  (cons "publicBlobBaseFee"
                        (or (fixture-object-field public-blob-base-fee-rpc
                                                  "result")
                            :false))
                  (cons "publicFeeHistoryOldestBlock"
                        (fixture-object-field public-fee-history
                                              "oldestBlock"))
                  (cons "publicFeeHistoryBaseFeeCount"
                        (length
                         (fixture-object-field public-fee-history
                                               "baseFeePerGas")))
                  (cons "publicFeeHistoryGasUsedRatioCount"
                        (length
                         (fixture-object-field public-fee-history
                                               "gasUsedRatio")))
                  (cons "publicBatchResponseCount"
                        (length public-batch-rpc))
                  (cons "publicBatchChainId"
                        (fixture-object-field public-batch-chain-id-rpc
                                              "result"))
                  (cons "publicBatchNetVersion"
                        (fixture-object-field public-batch-network-rpc
                                              "result"))
                  (cons "publicBatchClientVersion"
                        (fixture-object-field
                         public-batch-client-version-rpc
                         "result"))
                  (cons "pendingBlockReceipts"
                        (or (fixture-object-field
                             pending-block-receipts-rpc "result")
                            :false))
                  (cons "pendingUncleCount"
                        (fixture-object-field pending-uncle-count-rpc
                                              "result"))
                  (cons "pendingLogCount"
                        (length (fixture-object-field pending-logs-rpc
                                                      "result")))
                  (cons "newPayloadStatus"
                        (fixture-object-field new-payload-result "status"))
                  (cons "latestValidHash" expected-hash)
                  (cons "forkchoiceStatus"
                        (fixture-object-field forkchoice-status "status"))
                  (cons "enginePayloadBodiesByHashCount"
                        (length payload-bodies-by-hash-result))
                  (cons "enginePayloadBodiesByHashTransactionCount"
                        (length payload-body-by-hash-transactions))
                  (cons "enginePayloadBodiesByRangeCount"
                        (length payload-bodies-by-range-result))
                  (cons "enginePayloadBodiesByRangeTransactionCount"
                        (length payload-body-by-range-transactions))
                  (cons "preparedPayloadId" prepared-payload-id)
                  (cons "preparedPayloadParentHash"
                        (hash32-to-hex (block-hash child-block)))
                  (cons "preparedPayloadBlockNumber"
                        expected-prepared-block-number)
                  (cons "engineGetPayloadV2ParentHash"
                        (fixture-object-field
                         get-payload-execution-payload
                         "parentHash"))
                  (cons "engineGetPayloadV2BlockNumber"
                        (fixture-object-field
                         get-payload-execution-payload
                         "blockNumber"))
                  (cons "engineGetPayloadV2TransactionCount"
                        (length get-payload-transactions))
                  (cons "preparedTxpoolPayloadId"
                        prepared-txpool-payload-id)
                  (cons "engineGetPayloadV2TxpoolParentHash"
                        (fixture-object-field
                         get-txpool-payload-execution-payload
                         "parentHash"))
                  (cons "engineGetPayloadV2TxpoolBlockNumber"
                        (fixture-object-field
                         get-txpool-payload-execution-payload
                         "blockNumber"))
                  (cons "engineGetPayloadV2TxpoolTransactionCount"
                        (length get-txpool-payload-transactions))
                  (cons "engineGetPayloadV2TxpoolSelectedTransactionRaw"
                        (first get-txpool-payload-transactions))
                  (cons "engineGetPayloadV2TxpoolSelectedTransactionHash"
                        pending-transaction-hash-hex)
                  (cons "engineGetPayloadV2TxpoolSelectedStillPending"
                        (fixture-object-field
                         post-prepared-txpool-content-from-transaction
                         "hash"))
                  (cons "engineGetPayloadV2TxpoolNonSelectedBasefeeStillQueued"
                        (fixture-object-field
                         post-prepared-txpool-content-from-basefee-transaction
                         "hash"))
                  (cons "engineGetPayloadV2TxpoolNonSelectedQueuedStillQueued"
                        (fixture-object-field
                         post-prepared-txpool-content-from-queued-transaction
                         "hash"))
                  (cons "preparedReplacementTxpoolPayloadId"
                        prepared-replacement-txpool-payload-id)
                  (cons "engineGetPayloadV2TxpoolReplacementParentHash"
                        (fixture-object-field
                         get-replacement-txpool-payload-execution-payload
                         "parentHash"))
                  (cons "engineGetPayloadV2TxpoolReplacementBlockNumber"
                        (fixture-object-field
                         get-replacement-txpool-payload-execution-payload
                         "blockNumber"))
                  (cons "engineGetPayloadV2TxpoolReplacementTransactionCount"
                        (length get-replacement-txpool-payload-transactions))
                  (cons "engineGetPayloadV2TxpoolReplacementTransactionRaw"
                        (first get-replacement-txpool-payload-transactions))
                  (cons "engineGetPayloadV2TxpoolReplacementTransactionHash"
                        replacement-transaction-hash-hex)
                  (cons "engineGetPayloadV2TxpoolReplacementStillPending"
                        (fixture-object-field
                         post-replacement-txpool-content-from-transaction
                         "hash"))
                  (cons "engineGetPayloadV2TxpoolReplacementNonSelectedBasefeeStillQueued"
                        (fixture-object-field
                         post-replacement-txpool-content-from-basefee-transaction
                         "hash"))
                  (cons "engineGetPayloadV2TxpoolReplacementNonSelectedQueuedStillQueued"
                        (fixture-object-field
                         post-replacement-txpool-content-from-queued-transaction
                         "hash"))
                  (cons "engineNewPayloadV2TxpoolImportStatus"
                        (fixture-object-field
                         import-txpool-payload-result
                         "status"))
                  (cons "engineNewPayloadV2TxpoolImportLatestValidHash"
                        (fixture-object-field
                         import-txpool-payload-result
                         "latestValidHash"))
                  (cons "engineForkchoiceUpdatedV2TxpoolImportStatus"
                        (fixture-object-field
                         forkchoice-txpool-payload-status
                         "status"))
                  (cons "txpoolImportBlockHash"
                        replacement-txpool-block-hash)
                  (cons "txpoolImportBlockNumber"
                        expected-prepared-block-number)
                  (cons "txpoolImportTransactionHash"
                        (fixture-object-field
                         post-import-transaction
                         "hash"))
                  (cons "txpoolImportTransactionBlockHash"
                        (fixture-object-field
                         post-import-transaction
                         "blockHash"))
                  (cons "txpoolImportTransactionBlockNumber"
                        (fixture-object-field
                         post-import-transaction
                         "blockNumber"))
                  (cons "txpoolImportReceiptTransactionHash"
                        (fixture-object-field
                         post-import-receipt
                         "transactionHash"))
                  (cons "txpoolImportReceiptBlockHash"
                        (fixture-object-field
                         post-import-receipt
                         "blockHash"))
                  (cons "txpoolImportReceiptBlockNumber"
                        (fixture-object-field
                         post-import-receipt
                         "blockNumber"))
                  (cons "txpoolImportRawTransaction"
                        post-import-raw-transaction)
                  (cons "txpoolImportBlockTransactionCount"
                        (length post-import-block-transactions))
                  (cons "txpoolImportBlockTransactionHash"
                        (first post-import-block-transactions))
                  (cons "txpoolImportTxpoolStatusPending"
                        (fixture-object-field
                         post-import-txpool-status
                         "pending"))
                  (cons "txpoolImportTxpoolStatusQueued"
                        (fixture-object-field
                         post-import-txpool-status
                         "queued"))
                  (cons "txpoolImportSelectedStillPending"
                        (or (and post-import-txpool-content-from-selected
                                 (fixture-object-field
                                  post-import-txpool-content-from-selected
                                  "hash"))
                            :false))
                  (cons "txpoolImportNonSelectedBasefeeStillQueued"
                        (fixture-object-field
                         post-import-txpool-content-from-basefee-transaction
                         "hash"))
                  (cons "txpoolImportNonSelectedQueuedStillQueued"
                        (fixture-object-field
                         post-import-txpool-content-from-queued-transaction
                         "hash"))
                  (cons "remoteBlockHash" expected-remote-block-hash)
                  (cons "remoteBlockStatus"
                        (fixture-object-field remote-payload-result "status"))
                  (cons "invalidTipsetBlockHash"
                        expected-invalid-block-hash)
                  (cons "invalidTipsetStatus"
                        (fixture-object-field invalid-payload-result "status"))
                  (cons "invalidTipsetValidationError"
                        (fixture-object-field invalid-payload-result
                                              "validationError"))
                  (cons "txpoolPendingTransactionHash"
                        pending-transaction-hash-hex)
                  (cons "txpoolPendingTransactionRaw"
                        pending-transaction-raw)
                  (cons "txpoolReplacementTransactionHash"
                        replacement-transaction-hash-hex)
                  (cons "txpoolReplacementTransactionRaw"
                        replacement-transaction-raw)
                  (cons "txpoolPendingSender"
                        pending-transaction-sender-hex)
                  (cons "txpoolPendingNonce"
                        pending-transaction-nonce-key)
                  (cons "txpoolPendingSenderNonce"
                        (fixture-object-field pending-nonce-rpc "result"))
                  (cons "txpoolPendingInspectSummary"
                        txpool-inspect-transaction)
                  (cons "txpoolPendingFilterId" pending-filter-id)
                  (cons "txpoolPendingFilterHash"
                        (first pending-filter-changes))
                  (cons "txpoolPendingFilterChanges"
                        pending-filter-changes)
                  (cons "txpoolPendingFilterEmptyChanges"
                        empty-pending-filter-changes)
                  (cons "txpoolPendingFilterUninstallResult"
                        (fixture-object-field
                         uninstall-pending-filter-rpc
                         "result"))
                  (cons "txpoolPendingFilterMissingErrorCode"
                        (fixture-object-field
                         removed-pending-filter-error
                         "code"))
                  (cons "txpoolRejournalSeconds" 1)
                  (cons "txpoolRejournalObservedBeforeShutdown" t)
                  (cons "txpoolRejournalRecordCount"
                        (getf txpool-rejournal-report :record-count))
                  (cons "txpoolRejournalTransactionHash"
                        (getf txpool-rejournal-report
                              :transaction-hash))
                  (cons "txpoolRejournalSubpool"
                        (string-downcase
                         (symbol-name
                          (getf txpool-rejournal-report :subpool))))
                  (cons "devPeriodSeconds"
                        (getf dev-period-summary :dev-period-seconds))
                  (cons "devPeriodTransactionHash"
                        (getf dev-period-summary :transaction-hash))
                  (cons "devPeriodBlockNumber"
                        (getf dev-period-summary :block-number))
                  (cons "devPeriodBlockHash"
                        (getf dev-period-summary :block-hash))
                  (cons "devPeriodReceiptBlockNumber"
                        (getf dev-period-summary :receipt-block-number))
                  (cons "devPeriodReceiptBlockHash"
                        (getf dev-period-summary :receipt-block-hash))
                  (cons "devPeriodTransactionIndex"
                        (getf dev-period-summary :transaction-index))
                  (cons "devPeriodTxpoolStatusPending"
                        (getf dev-period-summary :txpool-status-pending))
                  (cons "devPeriodTxpoolStatusQueued"
                        (getf dev-period-summary :txpool-status-queued))
                  (cons "devPeriodPendingTransactionCount"
                        (getf dev-period-summary
                              :pending-transaction-count))
                  (cons "devPeriodEngineConnections"
                        (getf dev-period-summary :engine-connections))
                  (cons "devPeriodPublicConnections"
                        (getf dev-period-summary :public-connections))
                  (cons "devPeriodTotalConnections"
                        (getf dev-period-summary :total-connections))
                  (cons "txpoolBasefeeTransactionHash"
                        basefee-transaction-hash-hex)
                  (cons "txpoolBasefeeTransactionRaw"
                        basefee-transaction-raw)
                  (cons "txpoolBasefeeNonce"
                        basefee-transaction-nonce-key)
                  (cons "txpoolBasefeeInspectSummary"
                        txpool-inspect-basefee-transaction)
                  (cons "txpoolQueuedTransactionHash"
                        queued-transaction-hash-hex)
                  (cons "txpoolQueuedTransactionRaw"
                        queued-transaction-raw)
                  (cons "txpoolQueuedNonce"
                        queued-transaction-nonce-key)
                  (cons "txpoolQueuedInspectSummary"
                        txpool-inspect-queued-transaction)
                  (cons "txpoolStatusPending"
                        (fixture-object-field txpool-status "pending"))
                  (cons "txpoolStatusQueued"
                        (fixture-object-field txpool-status "queued"))
                  (cons "blockNumber" actual-block-number)
                  (cons "blockGasLimit"
                        (quantity-to-hex
                         (block-header-gas-limit
                          (block-header child-block))))
                  (cons "safeBlockNumber" expected-safe-block-number)
                  (cons "safeBlockGasLimit"
                        (quantity-to-hex
                         (block-header-gas-limit
                          (block-header parent-block))))
                  (cons "safeBlockHash"
                        (hash32-to-hex expected-safe-block-hash))
                  (cons "finalizedBlockNumber"
                        expected-finalized-block-number)
                  (cons "finalizedBlockHash"
                        (hash32-to-hex expected-finalized-block-hash))
                  (cons "checkedBalanceAddress"
                        (address-to-hex balance-address))
                  (cons "checkedBalanceField" balance-field)
                  (cons "checkedBalance" actual-balance)
                  (cons "checkedCheckpointBalance"
                        (getf (first checkpoint-balance-targets) :balance))
                  (cons "recipientBalance" actual-balance)
                  (cons "checkedBalanceCount" (length balance-targets))
                  (cons "transactionCount" (length transaction-checks))
                  (cons "checkedLogCount"
                        (reduce #'+ log-targets
                                :key (lambda (target)
                                       (getf target :count))
                                :initial-value 0))
                  (cons "checkedLogFilterCount"
                        (length log-targets))
                  (cons "checkedSimulationCount"
                        (if database-summary
                            (getf database-summary :rpc-simulation-count)
                            0))
                  (cons "checkedNonceAddress" (address-to-hex sender-address))
                  (cons "checkedNonce" expected-sender-nonce)
                  (cons "checkedCodeAddress" (address-to-hex code-address))
                  (cons "checkedCode" expected-code)
                  (cons "checkedStorageAddress"
                        (address-to-hex storage-address))
                  (cons "checkedStorageKey" storage-key)
                  (cons "checkedStorage" expected-storage)
                  (cons "checkedProofCodeHash"
                        (hash32-to-hex
                         (keccak-256-hash (hex-to-bytes expected-code))))
                  (cons "checkedProofStorageValue"
                        (quantity-to-hex (hex-to-quantity expected-storage)))
                  (cons "readyFile" (or ready-file :false))
                  (cons "engineEndpoint" +devnet-smoke-gate-engine-endpoint+)
                  (cons "rpcEndpoint" +devnet-smoke-gate-public-endpoint+)
                  (cons "logFile" (or log-file :false))
                  (cons "pidFile" (or pid-file :false))
                  (cons "databaseFile" (or database-file :false))
                  (cons "databasePruneStateBefore"
                        (or state-prune-before :false))
                  (cons "databasePrunedStateAvailable"
                        (if database-summary
                            (if (getf database-summary
                                      :pruned-state-available-p)
                                t
                                :false)
                            :false))
                  (cons "databaseHeadNumber"
                        (if database-summary
                            (quantity-to-hex
                             (getf database-summary :head-number))
                            :false))
                  (cons "databaseHeadGasLimit"
                        (if database-summary
                            (quantity-to-hex
                             (getf database-summary :head-gas-limit))
                            :false))
                  (cons "databaseSafeNumber"
                        (if database-summary
                            (quantity-to-hex
                             (getf database-summary :safe-number))
                            :false))
                  (cons "databaseSafeHash"
                        (if database-summary
                            (getf database-summary :safe-hash)
                            :false))
                  (cons "databaseFinalizedNumber"
                        (if database-summary
                            (quantity-to-hex
                             (getf database-summary :finalized-number))
                            :false))
                  (cons "databaseFinalizedHash"
                        (if database-summary
                            (getf database-summary :finalized-hash)
                            :false))
                  (cons "databaseRpcBlockNumber"
                        (if database-summary
                            (getf database-summary :rpc-block-number)
                            :false))
                  (cons "databaseRpcBalance"
                        (if database-summary
                            (getf database-summary :rpc-balance)
                            :false))
                  (cons "databaseRpcNonce"
                        (if database-summary
                            (getf database-summary :rpc-nonce)
                            :false))
                  (cons "databaseRpcCode"
                        (if database-summary
                            (getf database-summary :rpc-code)
                            :false))
                  (cons "databaseRpcStorage"
                        (if database-summary
                            (getf database-summary :rpc-storage)
                            :false))
                  (cons "databaseRpcPreparedPayloadId"
                        (if database-summary
                            (getf database-summary
                                  :rpc-prepared-payload-id)
                            :false))
                  (cons "databaseRpcPreparedPayloadParentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-prepared-payload-parent-hash)
                            :false))
                  (cons "databaseRpcPreparedPayloadBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-prepared-payload-block-number)
                            :false))
                  (cons "databaseRemoteBlockHash"
                        (if database-summary
                            (getf database-summary :remote-block-hash)
                            :false))
                  (cons "databaseRpcRemoteBlockStatus"
                        (if database-summary
                            (getf database-summary
                                  :rpc-remote-block-status)
                            :false))
                  (cons "databaseInvalidTipsetBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :invalid-tipset-block-hash)
                            :false))
                  (cons "databaseRpcInvalidTipsetStatus"
                        (if database-summary
                            (getf database-summary
                                  :rpc-invalid-tipset-status)
                            :false))
                  (cons "databaseRpcInvalidTipsetValidationError"
                        (if database-summary
                            (getf database-summary
                                  :rpc-invalid-tipset-validation-error)
                            :false))
                  (cons "databaseRpcTxpoolPendingHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolRawTransaction"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-raw-transaction)
                            :false))
                  (cons "databaseRpcTxpoolSender"
                        (if database-summary
                            (getf database-summary :rpc-txpool-sender)
                            :false))
                  (cons "databaseRpcTxpoolNonce"
                        (if database-summary
                            (getf database-summary :rpc-txpool-nonce)
                            :false))
                  (cons "databaseRpcTxpoolInspectSummary"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-inspect-summary)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeRawTransaction"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-raw-transaction)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeNonce"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-nonce)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeInspectSummary"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-inspect-summary)
                            :false))
                  (cons "databaseRpcTxpoolQueuedHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolQueuedRawTransaction"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-raw-transaction)
                            :false))
                  (cons "databaseRpcTxpoolQueuedNonce"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-nonce)
                            :false))
                  (cons "databaseRpcTxpoolQueuedInspectSummary"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-inspect-summary)
                            :false))
                  (cons "databaseRpcTxpoolStatusPending"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-status-pending)
                            :false))
                  (cons "databaseRpcTxpoolStatusQueued"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-status-queued)
                            :false))
                  (cons "databaseRpcTxpoolPendingBlockCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-block-count)
                            :false))
                  (cons "databaseRpcTxpoolPendingBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-block-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingBlockBaseFee"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-block-base-fee)
                            :false))
                  (cons "databaseRpcTxpoolPendingHeaderNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-header-number)
                            :false))
                  (cons "databaseRpcTxpoolPendingHeaderParentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-header-parent-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingHeaderHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-header-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingHeaderNonce"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-header-nonce)
                            :false))
                  (cons "databaseRpcTxpoolPendingHeaderBaseFee"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-header-base-fee)
                            :false))
                  (cons "databaseRpcTxpoolPendingFeeHistoryNextBaseFee"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-fee-history-next-base-fee)
                            :false))
                  (cons "databaseRpcTxpoolPendingSenderNonce"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-sender-nonce)
                            :false))
                  (cons "databaseRpcTxpoolPendingBlockTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-block-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingBlockTransactionBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-block-transaction-block-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingIndexHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-index-transaction-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingIndexBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-index-block-hash)
                            :false))
                  (cons "databaseRpcTxpoolPendingRawByIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-pending-raw-index-transaction)
                            :false))
                  (cons "databaseRpcTxpoolContentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-content-hash)
                            :false))
                  (cons "databaseRpcTxpoolContentFromHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-content-from-hash)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeContentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-content-hash)
                            :false))
                  (cons "databaseRpcTxpoolBasefeeContentFromHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-basefee-content-from-hash)
                            :false))
                  (cons "databaseRpcTxpoolQueuedContentHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-content-hash)
                            :false))
                  (cons "databaseRpcTxpoolQueuedContentFromHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-queued-content-from-hash)
                            :false))
                  (cons "databaseRpcTxpoolPublicConnections"
                        (if database-summary
                            (getf database-summary
                                  :rpc-txpool-public-connections)
                            :false))
                  (cons "databaseRpcProofAddress"
                        (if database-summary
                            (getf database-summary :rpc-proof-address)
                            :false))
                  (cons "databaseRpcProofCodeHash"
                        (if database-summary
                            (getf database-summary :rpc-proof-code-hash)
                            :false))
                  (cons "databaseRpcProofStorageKey"
                        (if database-summary
                            (getf database-summary :rpc-proof-storage-key)
                            :false))
                  (cons "databaseRpcProofStorageValue"
                        (if database-summary
                            (getf database-summary :rpc-proof-storage-value)
                            :false))
                  (cons "databaseRpcProofStorageCount"
                        (if database-summary
                            (getf database-summary :rpc-proof-storage-count)
                            :false))
                  (cons "databaseRpcProofAccountProofCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-proof-account-proof-count)
                            :false))
                  (cons "databaseRpcReceiptTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-receipt-transaction-hash)
                            :false))
                  (cons "databaseRpcReceiptBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-receipt-block-number)
                            :false))
                  (cons "databaseRpcBlockHash"
                        (if database-summary
                            (getf database-summary :rpc-block-hash)
                            :false))
                  (cons "databaseRpcBlockByHashNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-by-hash-number)
                            :false))
                  (cons "databaseRpcBlockTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-transaction-hash)
                            :false))
                  (cons "databaseRpcBlockByNumberHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-by-number-hash)
                            :false))
                  (cons "databaseRpcBlockByNumberNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-by-number-number)
                            :false))
                  (cons "databaseRpcBlockByNumberTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-by-number-transaction-hash)
                            :false))
                  (cons "databaseRpcFullBlockTransactionCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-transaction-count)
                            :false))
                  (cons "databaseRpcFullBlockTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-transaction-hash)
                            :false))
                  (cons "databaseRpcFullBlockTransactionIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-transaction-index)
                            :false))
                  (cons "databaseRpcFullBlockByNumberTransactionCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-by-number-transaction-count)
                            :false))
                  (cons "databaseRpcFullBlockByNumberTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-by-number-transaction-hash)
                            :false))
                  (cons "databaseRpcFullBlockByNumberTransactionIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-full-block-by-number-transaction-index)
                            :false))
                  (cons "databaseRpcTransactionHash"
                        (if database-summary
                            (getf database-summary :rpc-transaction-hash)
                            :false))
                  (cons "databaseRpcTransactionBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-block-hash)
                            :false))
                  (cons "databaseRpcTransactionBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-block-number)
                            :false))
                  (cons "databaseRpcBlockReceiptsCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-receipts-count)
                            :false))
                  (cons "databaseRpcBlockReceiptTransactionHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-receipt-transaction-hash)
                            :false))
                  (cons "databaseRpcBlockReceiptBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-receipt-block-hash)
                            :false))
                  (cons "databaseRpcBlockReceiptBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-receipt-block-number)
                            :false))
                  (cons "databaseRpcBlockTransactionCountByHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-transaction-count-by-hash)
                            :false))
                  (cons "databaseRpcBlockTransactionCountByNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-transaction-count-by-number)
                            :false))
                  (cons "databaseRpcCanonicalHashBalance"
                        (if database-summary
                            (getf database-summary
                                  :rpc-canonical-hash-balance)
                            :false))
                  (cons "databaseRpcCanonicalHashRequireBalance"
                        (if database-summary
                            (getf database-summary
                                  :rpc-canonical-hash-require-balance)
                            :false))
                  (cons "databaseRpcTransactionCount"
                        (if database-summary
                            (getf database-summary :rpc-transaction-count)
                            :false))
                  (cons "databaseRpcBalanceCount"
                        (if database-summary
                            (getf database-summary :rpc-balance-count)
                            :false))
                  (cons "databaseRpcLogCount"
                        (if database-summary
                            (getf database-summary :rpc-log-count)
                            :false))
                  (cons "databaseRpcLogFilterCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-log-filter-count)
                            :false))
                  (cons "databaseRpcLogFilterLogCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-log-filter-log-count)
                            :false))
                  (cons "databaseRpcLogFilterUninstallCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-log-filter-uninstall-count)
                            :false))
                  (cons "databaseRpcLogFilterMissingErrorCodes"
                        (if database-summary
                            (getf database-summary
                                  :rpc-log-filter-missing-error-codes)
                            :false))
                  (cons "databaseRpcBlockFilterId"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-filter-id)
                            :false))
                  (cons "databaseRpcBlockFilterChangeCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-filter-change-count)
                            :false))
                  (cons "databaseRpcBlockFilterGetLogsErrorCode"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-filter-get-logs-error-code)
                            :false))
                  (cons "databaseRpcBlockFilterUninstallResult"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-filter-uninstall-result)
                            :false))
                  (cons "databaseRpcBlockFilterMissingErrorCode"
                        (if database-summary
                            (getf database-summary
                                  :rpc-block-filter-missing-error-code)
                            :false))
                  (cons "databaseRpcRawTransactionByBlockHashAndIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-raw-transaction-by-hash)
                            :false))
                  (cons "databaseRpcRawTransactionByHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-raw-transaction)
                            :false))
                  (cons "databaseRpcRawTransactionByBlockNumberAndIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-raw-transaction-by-number)
                            :false))
                  (cons "databaseRpcTransactionByBlockHashAndIndexHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-hash-index-hash)
                            :false))
                  (cons "databaseRpcTransactionByBlockHashAndIndexBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-hash-index-block-hash)
                            :false))
                  (cons "databaseRpcTransactionByBlockHashAndIndexBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-hash-index-block-number)
                            :false))
                  (cons "databaseRpcTransactionByBlockHashAndIndexIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-hash-index-transaction-index)
                            :false))
                  (cons "databaseRpcTransactionByBlockNumberAndIndexHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-number-index-hash)
                            :false))
                  (cons "databaseRpcTransactionByBlockNumberAndIndexBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-number-index-block-hash)
                            :false))
                  (cons "databaseRpcTransactionByBlockNumberAndIndexBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-number-index-block-number)
                            :false))
                  (cons "databaseRpcTransactionByBlockNumberAndIndexIndex"
                        (if database-summary
                            (getf database-summary
                                  :rpc-transaction-by-number-index-transaction-index)
                            :false))
                  (cons "databaseRpcSafeBlockHash"
                        (if database-summary
                            (getf database-summary :rpc-safe-block-hash)
                            :false))
                  (cons "databaseRpcSafeBlockNumber"
                        (if database-summary
                            (getf database-summary :rpc-safe-block-number)
                            :false))
                  (cons "databaseRpcFinalizedBlockHash"
                        (if database-summary
                            (getf database-summary
                                  :rpc-finalized-block-hash)
                            :false))
                  (cons "databaseRpcFinalizedBlockNumber"
                        (if database-summary
                            (getf database-summary
                                  :rpc-finalized-block-number)
                            :false))
                  (cons "databaseRpcCallResult"
                        (if database-summary
                            (getf database-summary :rpc-call-result)
                            :false))
                  (cons "databaseRpcFailedCallError"
                        (if database-summary
                            (getf database-summary
                                  :rpc-failed-call-error-message)
                            :false))
                  (cons "databaseRpcEstimateGas"
                        (if database-summary
                            (getf database-summary :rpc-estimate-gas)
                            :false))
                  (cons "databaseRpcAccessListCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-access-list-count)
                            :false))
                  (cons "databaseRpcAccessListGasUsed"
                        (if database-summary
                            (getf database-summary
                                  :rpc-access-list-gas-used)
                            :false))
                  (cons "databaseRpcPostCallStorage"
                        (if database-summary
                            (getf database-summary
                                  :rpc-post-call-storage)
                            :false))
                  (cons "databaseRpcSimulationCount"
                        (if database-summary
                            (getf database-summary
                                  :rpc-simulation-count)
                            :false))
                  (cons "databaseRpcPrunedStateError"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-pruned-state-error-message)
                                :false)
                            :false))
                  (cons "databaseRpcPrunedStateErrors"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-pruned-state-error-messages)
                                :false)
                            :false))
                  (cons "databaseRpcPublicConnections"
                        (if database-summary
                            (getf database-summary :rpc-public-connections)
                            :false))
                  (cons "databaseRpcSideBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideForkchoiceStatus"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-forkchoice-status)
                                :false)
                            :false))
                  (cons "databaseRpcSideRejectedCheckpointError"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-rejected-checkpoint-error)
                                :false)
                            :false))
                  (cons "databaseRpcSideBlockNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-block-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideLatestBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-latest-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideTransactionReinserted"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-transaction-reinserted-p)
                                :false)
                            :false))
                  (cons "databaseRpcSideTransactionByHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-transaction-by-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRawTransaction"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-raw-transaction)
                                :false)
                            :false))
                  (cons "databaseRpcSidePendingTransaction"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-pending-transaction)
                                :false)
                            :false))
                  (cons "databaseRpcSideReinsertedTransactionCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-reinserted-transaction-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideReinsertedTransactionHashes"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-reinserted-transaction-hashes)
                                :false)
                            :false))
                  (cons "databaseRpcSideReceipt"
                        (if database-summary
                            (or (getf database-summary :rpc-side-receipt)
                                :false)
                            :false))
                  (cons "databaseRpcSideHiddenReceiptCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-hidden-receipt-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideChildBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-child-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideBlockReceiptsCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-block-receipts-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideLogCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-log-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredHeadNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-head-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredHeadHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-head-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcBlockNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-block-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcLatestBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-latest-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredSafeNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-safe-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredSafeHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-safe-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredFinalizedNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-finalized-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredFinalizedHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-finalized-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcSafeNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-safe-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcSafeHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-safe-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcFinalizedNumber"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-finalized-number)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRpcFinalizedHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-rpc-finalized-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredSafeBalance"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-safe-balance)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredFinalizedBalance"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-finalized-balance)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredRawTransaction"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-raw-transaction)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredPendingTransaction"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-pending-transaction)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredReinsertedTransactionCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-reinserted-transaction-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredReinsertedTransactionHashes"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-reinserted-transaction-hashes)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredReceipt"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-receipt)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredHiddenReceiptCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-hidden-receipt-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredChildBlockHash"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-child-block-hash)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredChildRequireCanonicalError"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-child-require-canonical-error)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredChildRequireCanonicalErrors"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-child-require-canonical-errors)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredBlockReceiptsCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-block-receipts-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredLogCount"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-log-count)
                                :false)
                            :false))
                  (cons "databaseRpcSideRestoredPublicConnections"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-restored-public-connections)
                                :false)
                            :false))
                  (cons "databaseRpcSideTotalConnections"
                        (if database-summary
                            (let ((side-engine
                                    (getf database-summary
                                          :rpc-side-engine-connections))
                                  (side-public
                                    (getf database-summary
                                          :rpc-side-public-connections))
                                  (side-restored-public
                                    (getf database-summary
                                          :rpc-side-restored-public-connections)))
                              (if (and side-engine
                                       side-public
                                       side-restored-public)
                                  (+ side-engine
                                     side-public
                                     side-restored-public)
                                  :false))
                            :false))
                  (cons "databaseRpcSideEngineConnections"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-engine-connections)
                                :false)
                            :false))
                  (cons "databaseRpcSidePublicConnections"
                        (if database-summary
                            (or (getf database-summary
                                      :rpc-side-public-connections)
                                :false)
                            :false))))))))))))
             (let* ((ready-summary
                      (when ready-file
                        (devnet-smoke-gate-verify-ready-file
                         ready-file
                         (devnet-smoke-gate-field report "safeBlockNumber")
                         (devnet-smoke-gate-field report "safeBlockHash")
                         :expected-head-gas-limit
                         (devnet-smoke-gate-field report "safeBlockGasLimit")
                         :expected-engine-endpoint
                         (devnet-smoke-gate-field report "engineEndpoint")
                         :expected-rpc-endpoint
                         (devnet-smoke-gate-field report "rpcEndpoint"))))
                    (ready-process-id
                      (and ready-summary
                           (fixture-object-field ready-summary "processId")))
                    (pid-file-process-id
                      (when pid-file
                        (devnet-smoke-gate-verify-pid-file
                         pid-file
                         :expected-process-id ready-process-id)))
                    (expected-process-id
                      (or pid-file-process-id ready-process-id)))
               (when log-file
                 (devnet-smoke-gate-verify-log-file
	                  log-file
	                  (devnet-smoke-gate-field report "safeBlockNumber")
	                  (devnet-smoke-gate-field report "safeBlockHash")
	                  (devnet-smoke-gate-field report
	                                           "txpoolImportBlockNumber")
	                  (devnet-smoke-gate-field report
	                                           "txpoolImportBlockHash")
                  :ready-head-gas-limit
                  (devnet-smoke-gate-field report "safeBlockGasLimit")
                  :shutdown-head-gas-limit
                  (devnet-smoke-gate-field report "blockGasLimit")
                  :expected-process-id expected-process-id
                  :expected-connection-summary
                  (list :engine-connections
                        (fixture-object-field report "engineConnections")
                        :public-connections
                        (fixture-object-field report "publicConnections")
                        :total-connections
                        (fixture-object-field report "totalConnections"))
                  :expected-engine-endpoint
                  (devnet-smoke-gate-field report "engineEndpoint")
                  :expected-rpc-endpoint
                  (devnet-smoke-gate-field report "rpcEndpoint")))
               report)))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file journal-path)
        (delete-file journal-path))))
  #-sbcl
  (error "Devnet smoke gate requires SBCL threads"))
