(in-package #:ethereum-lisp.test)

(deftest devnet-node-loads-genesis-summary
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 0))
         (summary (ethereum-lisp.cli:devnet-node-summary node))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (head (ethereum-lisp.cli:devnet-node-genesis-block node))
         (head-hash (block-hash head))
         (funded (address-from-hex "0x0000000000000000000000000000000000001001")))
    (is (= 1337 (getf summary :chain-id)))
    (is (= 0 (getf summary :head-number)))
    (is (string= "127.0.0.1:0" (getf summary :engine-endpoint)))
    (is (string= "127.0.0.1:8545" (getf summary :rpc-endpoint)))
    (is (string= "/" (getf summary :engine-rpc-prefix)))
    (is (string= "/" (getf summary :public-rpc-prefix)))
    (is (equal (devnet-cli-current-process-id) (getf summary :process-id)))
    (is (string= (hash32-to-hex head-hash) (getf summary :head-hash)))
    (is (null (getf summary :safe-number)))
    (is (null (getf summary :safe-hash)))
    (is (null (getf summary :finalized-number)))
    (is (null (getf summary :finalized-hash)))
    (is (getf summary :state-available-p))
    (is (not (getf summary :auth-required-p)))
    (is (not (getf summary :jwt-secret-path)))
    (is (null (getf summary :public-api-modules)))
    (is (string= "/"
                 (engine-rpc-http-service-rpc-prefix
                  (ethereum-lisp.cli:devnet-node-service node))))
    (is (string= "/"
                 (engine-rpc-http-service-rpc-prefix
                  (ethereum-lisp.cli:devnet-node-public-service node))))
    (is (funcall (engine-rpc-http-service-allowed-method-p
                  (ethereum-lisp.cli:devnet-node-service node))
                 "engine_exchangeCapabilities"))
    (is (not (funcall (engine-rpc-http-service-allowed-method-p
                       (ethereum-lisp.cli:devnet-node-service node))
                      "eth_chainId")))
    (is (funcall (engine-rpc-http-service-allowed-method-p
                  (ethereum-lisp.cli:devnet-node-public-service node))
                 "eth_chainId"))
    (is (not (funcall (engine-rpc-http-service-allowed-method-p
                       (ethereum-lisp.cli:devnet-node-public-service node))
                      "engine_exchangeCapabilities")))
    (is (= #xde0b6b3a7640000
           (chain-store-account-balance store head-hash funded)))))

(deftest devnet-node-splits-engine-and-public-rpc-methods
  (let* ((coinbase
           (address-from-hex "0x00000000000000000000000000000000000000cb"))
         (node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545
                :network-id 7331
                :coinbase coinbase))
         (engine-service (ethereum-lisp.cli:devnet-node-service node))
         (public-service (ethereum-lisp.cli:devnet-node-public-service node))
         (engine-store (engine-rpc-http-service-store engine-service))
         (engine-config (engine-rpc-http-service-config engine-service))
         (public-filter (engine-rpc-http-service-allowed-method-p
                         public-service))
         (engine-filter (engine-rpc-http-service-allowed-method-p
                         engine-service)))
    (let ((engine-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_chainId\",\"params\":[]}"
              engine-store
              engine-config
              :allowed-method-p engine-filter)))
         (public-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}"
              engine-store
              engine-config
              :allowed-method-p public-filter)))
          (engine-rpc-modules-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"rpc_modules\",\"params\":[]}"
              engine-store
              engine-config
              :allowed-method-p engine-filter)))
          (public-rpc-modules-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"rpc_modules\",\"params\":[]}"
              engine-store
              engine-config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter)))
          (chain-id-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"eth_chainId\",\"params\":[]}"
              engine-store
              engine-config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :coinbase
              (ethereum-lisp.core::engine-rpc-http-service-coinbase
               public-service)
              :allowed-method-p public-filter)))
          (public-coinbase-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"eth_coinbase\",\"params\":[]}"
              engine-store
              engine-config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :coinbase
              (ethereum-lisp.core::engine-rpc-http-service-coinbase
               public-service)
              :allowed-method-p public-filter)))
          (network-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"net_version\",\"params\":[]}"
              engine-store
              engine-config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter))))
      (is (string= (address-to-hex coinbase)
                   (getf (ethereum-lisp.cli:devnet-node-summary node)
                         :coinbase)))
      (is (bytes= (address-bytes coinbase)
                  (address-bytes
                   (ethereum-lisp.core::engine-rpc-http-service-coinbase
                    engine-service))))
      (is (bytes= (address-bytes coinbase)
                  (address-bytes
                   (ethereum-lisp.core::engine-rpc-http-service-coinbase
                    public-service))))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field engine-response "error")
              "code")))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field public-response "error")
              "code")))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field engine-rpc-modules-response "error")
              "code")))
      (let ((modules
              (fixture-object-field public-rpc-modules-response "result")))
        (is (string= "1.0" (fixture-object-field modules "eth")))
        (is (string= "1.0" (fixture-object-field modules "net")))
        (is (string= "1.0" (fixture-object-field modules "rpc")))
        (is (string= "1.0" (fixture-object-field modules "txpool")))
        (is (string= "1.0" (fixture-object-field modules "web3"))))
      (is (string= "0x539"
                   (fixture-object-field chain-id-response "result")))
      (is (string= (address-to-hex coinbase)
                   (fixture-object-field public-coinbase-response
                                         "result")))
      (is (string= "7331"
                   (fixture-object-field network-response "result"))))))

(deftest devnet-node-public-http-api-filter-limits-modules
  (let* ((options
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet" "--http.api" "eth,net")))
         (http-api-modules (getf options :http-api-modules))
         (node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :public-allowed-method-p
                (ethereum-lisp.cli::devnet-cli-public-api-method-filter
                 http-api-modules)
                :public-api-modules http-api-modules))
         (public-service (ethereum-lisp.cli:devnet-node-public-service node))
         (summary (ethereum-lisp.cli:devnet-node-summary node))
         (summary-json
           (ethereum-lisp.cli::devnet-node-summary-json-object node))
         (store (engine-rpc-http-service-store public-service))
         (config (engine-rpc-http-service-config public-service))
         (public-filter (engine-rpc-http-service-allowed-method-p
                         public-service)))
    (is (equal '("eth" "net") http-api-modules))
    (is (equal '("eth" "net") (getf summary :public-api-modules)))
    (is (equal '("eth" "net")
               (cdr (assoc "publicApiModules" summary-json :test #'string=))))
    (is (funcall public-filter "eth_chainId"))
    (is (funcall public-filter "net_version"))
    (is (funcall public-filter "rpc_modules"))
    (is (not (funcall public-filter "web3_clientVersion")))
    (is (not (funcall public-filter "txpool_status")))
    (is (not (funcall public-filter "engine_exchangeCapabilities")))
    (let ((chain-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_chainId\",\"params\":[]}"
              store
              config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter)))
          (web3-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"web3_clientVersion\",\"params\":[]}"
              store
              config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter)))
          (rpc-modules-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"rpc_modules\",\"params\":[]}"
              store
              config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter)))
          (txpool-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"txpool_status\",\"params\":[]}"
              store
              config
              :network-id
              (ethereum-lisp.core::engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter))))
      (is (string= "0x539"
                   (fixture-object-field chain-response "result")))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field web3-response "error")
              "code")))
      (let ((modules
              (fixture-object-field rpc-modules-response "result")))
        (is (string= "1.0" (fixture-object-field modules "eth")))
        (is (string= "1.0" (fixture-object-field modules "net")))
        (is (string= "1.0" (fixture-object-field modules "rpc")))
        (is (not (fixture-object-field modules "txpool")))
        (is (not (fixture-object-field modules "web3"))))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field txpool-response "error")
              "code"))))))

(deftest devnet-node-start-serves-engine-and-public-listeners
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (engine-accepted-p nil)
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "engine"
             :accept-function
             (lambda ()
               (unless engine-accepted-p
                 (setf engine-accepted-p t)
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream "GET / HTTP/1.1\r\n\r\n")
                  :output-stream (make-string-output-stream)
                  :close-function (lambda () nil))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "public"
             :accept-function
             (lambda ()
               (loop until engine-accepted-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream "GET / HTTP/1.1\r\n\r\n")
                :output-stream (make-string-output-stream)
                :close-function (lambda () nil)))
             :close-function (lambda () nil))
            :max-connections 1)))
    (is (= 1 (getf summary :engine-connections)))
    (is (= 1 (getf summary :public-connections)))
    (is (= 2 (getf summary :total-connections)))))

(deftest devnet-node-start-serves-engine-only-when-public-listener-is-disabled
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-devnet-cli-one-shot-listener "engine")
            nil
            :max-connections 1)))
    (is (= 1 (getf summary :engine-connections)))
    (is (= 0 (getf summary :public-connections)))
    (is (= 1 (getf summary :total-connections)))))

(deftest devnet-node-split-listeners-serve-authenticated-engine-and-public-rpc
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 8551
                         :public-port 8545
                         :jwt-secret-path (namestring jwt-path)
                         :engine-rpc-prefix "/engine"
                         :public-rpc-prefix "/rpc"))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (engine-body
                    (concatenate
                     'string
                     "{\"jsonrpc\":\"2.0\",\"id\":11,"
                     "\"method\":\"engine_getClientVersionV1\","
                     "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
                     "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
                  (public-body
                    "{\"jsonrpc\":\"2.0\",\"id\":12,\"method\":\"eth_chainId\",\"params\":[]}")
                  (engine-output (make-string-output-stream))
                  (public-output (make-string-output-stream))
                  (engine-accepted-p nil)
                  (engine-closed-p nil)
                  (public-closed-p nil)
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "engine"
                      :accept-function
                      (lambda ()
                        (unless engine-accepted-p
                          (setf engine-accepted-p t)
                          (make-engine-rpc-http-connection
                           :input-stream
                           (make-string-input-stream
                            (devnet-cli-json-rpc-http-request
                             engine-body
                             :token token
                             :target "/engine"))
                           :output-stream engine-output
                           :close-function
                           (lambda () (setf engine-closed-p t)))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "public"
                      :accept-function
                      (lambda ()
                        (loop until engine-accepted-p
                              do (sleep 0.001))
                        (make-engine-rpc-http-connection
                         :input-stream
                         (make-string-input-stream
                          (devnet-cli-json-rpc-http-request
                           public-body
                           :target "/rpc"))
                         :output-stream public-output
                         :close-function
                         (lambda () (setf public-closed-p t))))
                      :close-function (lambda () nil))
                     :max-connections 1)))
             (is (= 1 (getf summary :engine-connections)))
             (is (= 1 (getf summary :public-connections)))
             (is (= 2 (getf summary :total-connections)))
             (is engine-closed-p)
             (is public-closed-p)
             (let* ((engine-response (get-output-stream-string engine-output))
                    (public-response (get-output-stream-string public-output))
                    (engine-rpc (parse-json
                                 (devnet-cli-http-body engine-response)))
                    (public-rpc (parse-json
                                 (devnet-cli-http-body public-response)))
                    (local-client
                      (first (fixture-object-field engine-rpc "result"))))
               (is (= 200 (devnet-cli-http-status engine-response)))
               (is (= 200 (devnet-cli-http-status public-response)))
               (is (= 11 (fixture-object-field engine-rpc "id")))
               (is (string= "ethereum-lisp"
                            (fixture-object-field local-client "name")))
               (is (= 12 (fixture-object-field public-rpc "id")))
               (is (string= "0x539"
                            (fixture-object-field public-rpc "result"))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path)))))

(deftest devnet-node-split-listeners-import-payload-and-serve-public-state
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((case
                    (select-engine-newpayload-v2-fixture-case
                     +engine-newpayload-v2-fixture-path+
                     "shanghai-one-transfer-with-withdrawal"))
                  (node (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 8551
                         :public-port 8545
                         :jwt-secret-path (namestring jwt-path)))
                  (store (make-engine-payload-memory-store))
                  (config (engine-fixture-chain-config case))
                  (parent (fixture-object-field case "parent"))
                  (payload-case (fixture-object-field case "payload"))
                  (expect (fixture-object-field case "expect"))
                  (parent-state (engine-fixture-parent-state parent))
                  (fee-recipient (fixture-address-field parent "feeRecipient"))
                  (transactions
                    (mapcar (lambda (raw)
                              (transaction-from-encoding (hex-to-bytes raw)))
                            (fixture-object-field payload-case
                                                  "transactions")))
                  (withdrawals
                    (mapcar #'engine-fixture-withdrawal
                            (fixture-object-field payload-case
                                                  "withdrawals")))
                  (parent-header
                    (make-block-header
                     :parent-hash (zero-hash32)
                     :beneficiary fee-recipient
                     :state-root (state-db-root parent-state)
                     :mix-hash (zero-hash32)
                     :number (fixture-quantity-field parent "number")
                     :gas-limit (fixture-quantity-field parent "gasLimit")
                     :gas-used (fixture-quantity-field parent "gasUsed")
                     :timestamp (fixture-quantity-field parent "timestamp")
                     :base-fee-per-gas
                     (fixture-quantity-field parent "baseFeePerGas")
                     :withdrawals-root (withdrawal-list-root '())))
                  (parent-block (make-block :header parent-header))
                  (child-state (state-db-copy parent-state))
                  (child-header
                    (make-block-header
                     :parent-hash (block-hash parent-block)
                     :beneficiary fee-recipient
                     :mix-hash (zero-hash32)
                     :number (fixture-quantity-field payload-case "number")
                     :gas-limit (fixture-quantity-field payload-case
                                                        "gasLimit")
                     :gas-used 0
                     :timestamp (fixture-quantity-field payload-case
                                                        "timestamp")
                     :base-fee-per-gas
                     (fixture-quantity-field payload-case "baseFeePerGas")))
                  (child-block
                    (execute-signed-block
                     child-state
                     transactions
                     :expected-chain-id (chain-config-chain-id config)
                     :header child-header
                     :chain-config config
                     :withdrawals withdrawals))
                  (payload
                    (execution-payload-envelope-execution-payload
                     (block-to-executable-data child-block)))
                  (recipient (fixture-address-field expect "recipient"))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (new-payload-output (make-string-output-stream))
                  (forkchoice-output (make-string-output-stream))
                  (block-number-output (make-string-output-stream))
                  (balance-output (make-string-output-stream))
                  (engine-requests
                    (list
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
                     forkchoice-output)))
                  (public-requests
                    (list
                     (cons
                      (json-encode
                       (list (cons "jsonrpc" "2.0")
                             (cons "id" 31)
                             (cons "method" "eth_blockNumber")
                             (cons "params" '())))
                      block-number-output)
                     (cons
                      (json-encode
                       (engine-fixture-balance-request 32 recipient))
                      balance-output)))
                  (engine-served-count 0)
                  (engine-done-p nil)
                  (public-served-count 0))
             (devnet-cli-set-node-store-config node store config)
             (engine-payload-store-put-block
              store parent-block :state-available-p t)
             (commit-state-db-to-chain-store
              store (block-hash parent-block) parent-state)
             (let ((summary
                     (ethereum-lisp.cli:start-devnet-node-listeners
                      node
                      (make-engine-rpc-http-listener
                       :endpoint "engine"
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
                                (when (= engine-served-count 2)
                                  (setf engine-done-p t)))))))
                       :close-function (lambda () nil))
                      (make-engine-rpc-http-listener
                       :endpoint "public"
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
                              :close-function
                              (lambda () (incf public-served-count))))))
                       :close-function (lambda () nil))
                      :max-connections 2)))
               (is (= 2 (getf summary :engine-connections)))
               (is (= 2 (getf summary :public-connections)))
               (is (= 4 (getf summary :total-connections)))
               (is (= 2 engine-served-count))
               (is (= 2 public-served-count))
               (let* ((new-payload-response
                        (get-output-stream-string new-payload-output))
                      (forkchoice-response
                        (get-output-stream-string forkchoice-output))
                      (block-number-response
                        (get-output-stream-string block-number-output))
                      (balance-response
                        (get-output-stream-string balance-output))
                      (new-payload-rpc
                        (parse-json
                         (devnet-cli-http-body new-payload-response)))
                      (forkchoice-rpc
                        (parse-json
                         (devnet-cli-http-body forkchoice-response)))
                      (block-number-rpc
                        (parse-json
                         (devnet-cli-http-body block-number-response)))
                      (balance-rpc
                        (parse-json
                         (devnet-cli-http-body balance-response)))
                      (new-payload-result
                        (fixture-object-field new-payload-rpc "result"))
                      (forkchoice-status
                        (fixture-object-field
                         (fixture-object-field forkchoice-rpc "result")
                         "payloadStatus")))
                 (is (= 200 (devnet-cli-http-status new-payload-response)))
                 (is (= 200 (devnet-cli-http-status forkchoice-response)))
                 (is (= 200 (devnet-cli-http-status block-number-response)))
                 (is (= 200 (devnet-cli-http-status balance-response)))
                 (is (string= +payload-status-valid+
                              (fixture-object-field new-payload-result
                                                    "status")))
                 (is (string= (hash32-to-hex (block-hash child-block))
                              (fixture-object-field new-payload-result
                                                    "latestValidHash")))
                 (is (string= +payload-status-valid+
                              (fixture-object-field forkchoice-status
                                                    "status")))
                 (is (string= (fixture-object-field payload-case "number")
                              (fixture-object-field block-number-rpc
                                                    "result")))
                 (is (string= (fixture-object-field expect
                                                    "recipientBalance")
                              (fixture-object-field balance-rpc
                                                    "result")))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path)))))

(deftest devnet-node-start-closes-engine-listener-on-public-error
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (engine-closed-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "engine"
            :accept-function
            (lambda ()
              (loop until engine-closed-p
                    do (sleep 0.001))
              nil)
            :close-function (lambda () (setf engine-closed-p t))))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "public"
            :accept-function (lambda () (error "public listener failed"))
            :close-function (lambda () nil))))
    (signals error
      (ethereum-lisp.cli:start-devnet-node-listeners
       node
       engine-listener
       public-listener
       :max-connections 1))
    (is engine-closed-p)))

(deftest devnet-node-start-closes-public-listener-on-engine-error
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (engine-closed-p nil)
         (public-closed-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "engine"
            :accept-function (lambda () (error "engine listener failed"))
            :close-function (lambda () (setf engine-closed-p t))))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "public"
            :accept-function
            (lambda ()
              (loop until public-closed-p
                    do (sleep 0.001))
              nil)
            :close-function (lambda () (setf public-closed-p t)))))
    (signals error
      (ethereum-lisp.cli:start-devnet-node-listeners
       node
       engine-listener
       public-listener
       :max-connections 1))
    (is engine-closed-p)
    (is public-closed-p)))

(deftest devnet-shutdown-controller-stops-split-listeners
  #-sbcl
  (skip-test "Devnet split listener shutdown requires SBCL threads")
  #+sbcl
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (controller
           (ethereum-lisp.cli:make-devnet-shutdown-controller))
         (engine-accepting-p nil)
         (public-accepting-p nil)
         (engine-closed-p nil)
         (public-closed-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "engine"
            :accept-function
            (lambda ()
              (setf engine-accepting-p t)
              (loop until engine-closed-p
                    do (sleep 0.001))
              nil)
            :close-function (lambda () (setf engine-closed-p t))))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "public"
            :accept-function
            (lambda ()
              (setf public-accepting-p t)
              (loop until public-closed-p
                    do (sleep 0.001))
              nil)
            :close-function (lambda () (setf public-closed-p t))))
         (summary nil))
    (let ((serve-thread
            (sb-thread:make-thread
             (lambda ()
               (setf summary
                     (ethereum-lisp.cli:start-devnet-node-listeners
                      node
                      engine-listener
                      public-listener
                      :shutdown-controller controller)))
             :name "ethereum-lisp-devnet-shutdown-test")))
      (loop repeat 1000
            until (and engine-accepting-p public-accepting-p)
            do (sleep 0.001))
      (is engine-accepting-p)
      (is public-accepting-p)
      (is (not (ethereum-lisp.cli:devnet-shutdown-requested-p controller)))
      (is (ethereum-lisp.cli:devnet-shutdown-request controller))
      (sb-thread:join-thread serve-thread)
      (is (ethereum-lisp.cli:devnet-shutdown-requested-p controller))
      (is engine-closed-p)
      (is public-closed-p)
      (is (= 0 (getf summary :engine-connections)))
      (is (= 0 (getf summary :public-connections)))
      (is (= 0 (getf summary :total-connections))))))

(deftest devnet-listener-ready-callback-reports-bound-endpoints
  #-sbcl
  (skip-test "Devnet split listener serving requires SBCL threads")
  #+sbcl
  (let* ((ready-path
           (devnet-cli-temp-path "ethereum-lisp-devnet-bound-ready" "json"))
         (sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
         (node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 0
                :public-port 0
                :telemetry-sink sink))
         (callback-called-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "127.0.0.1:18551"
            :accept-function (lambda () nil)
            :close-function (lambda () nil)))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "127.0.0.1:18545"
            :accept-function (lambda () nil)
            :close-function (lambda () nil))))
    (unwind-protect
         (let ((summary
                 (ethereum-lisp.cli:start-devnet-node-listeners
                  node
                  engine-listener
                  public-listener
                  :max-connections 0
                  :on-listeners-ready
                  (lambda (engine public)
                    (setf callback-called-p t)
                    (ethereum-lisp.cli::devnet-cli-write-ready-file
                     node
                     ready-path
                     :engine-endpoint
                     (engine-rpc-http-listener-endpoint engine)
                     :rpc-endpoint
                     (engine-rpc-http-listener-endpoint public))
                    (ethereum-lisp.cli::devnet-cli-log-event
                     node
                     "devnet.ready"
                     :engine-endpoint
                     (engine-rpc-http-listener-endpoint engine)
                     :rpc-endpoint
                     (engine-rpc-http-listener-endpoint public))))))
           (is callback-called-p)
           (is (= 0 (getf summary :engine-connections)))
           (is (= 0 (getf summary :public-connections)))
           (ethereum-lisp.cli::devnet-cli-log-event
            node
            "devnet.shutdown"
            :engine-endpoint
            (engine-rpc-http-listener-endpoint engine-listener)
            :rpc-endpoint
            (engine-rpc-http-listener-endpoint public-listener)
            :connection-summary summary)
           (let ((ready-summary
                   (parse-json (devnet-cli-file-string ready-path))))
             (is (string= "127.0.0.1:18551"
                          (fixture-object-field ready-summary
                                                "engineEndpoint")))
             (is (string= "127.0.0.1:18545"
                          (fixture-object-field ready-summary
                                                "rpcEndpoint")))
             (is (equal (devnet-cli-current-process-id)
                        (fixture-object-field ready-summary
                                              "processId"))))
           (let ((events
                   (remove-if-not
                    (lambda (event)
                      (member
                       (ethereum-lisp.telemetry:telemetry-event-name event)
                       '("devnet.ready" "devnet.shutdown")
                       :test #'string=))
                    (ethereum-lisp.telemetry:telemetry-events sink))))
             (is (= 2 (length events)))
             (dolist (event events)
               (let ((fields
                       (ethereum-lisp.telemetry:telemetry-event-fields
                        event)))
                 (is (string= "127.0.0.1:18551"
                              (cdr (assoc "engineEndpoint" fields
                                          :test #'string=))))
                 (is (string= "127.0.0.1:18545"
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))
                 (is (string= (if (string= "devnet.ready"
                                            (ethereum-lisp.telemetry:telemetry-event-name
                                             event))
                                   "ready"
                                   "shutdown")
                              (cdr (assoc "lifecyclePhase" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "engineConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "publicConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "totalConnections" fields
                                          :test #'string=))))
                 (is (string= (devnet-cli-current-process-id-string)
                              (cdr (assoc "processId" fields
                                          :test #'string=))))))))
      (when (probe-file ready-path)
        (delete-file ready-path)))))

(deftest devnet-listener-ready-callback-error-closes-listeners
  #-sbcl
  (skip-test "Devnet split listener serving requires SBCL threads")
  #+sbcl
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (engine-closed-p nil)
         (public-closed-p nil)
         (engine-listener
           (make-engine-rpc-http-listener
            :endpoint "engine"
            :accept-function (lambda () nil)
            :close-function (lambda () (setf engine-closed-p t))))
         (public-listener
           (make-engine-rpc-http-listener
            :endpoint "public"
            :accept-function (lambda () nil)
            :close-function (lambda () (setf public-closed-p t)))))
    (signals error
      (ethereum-lisp.cli:start-devnet-node-listeners
       node
       engine-listener
       public-listener
       :max-connections 0
       :on-listeners-ready
       (lambda (engine public)
         (declare (ignore engine public))
         (error "listener ready callback failed"))))
    (is engine-closed-p)
    (is public-closed-p)))

(deftest devnet-node-loads-jwt-secret-file
  (let ((path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            path
            (format nil "0x~A~%" +devnet-cli-jwt-secret+))
           (let* ((node (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 0
                         :jwt-secret-path (namestring path)))
                  (summary (ethereum-lisp.cli:devnet-node-summary node))
                  (service (ethereum-lisp.cli:devnet-node-service node)))
             (is (getf summary :auth-required-p))
             (is (string= (namestring path)
                          (getf summary :jwt-secret-path)))
             (is (= 32 (length (engine-rpc-http-service-jwt-secret service))))))
      (when (probe-file path)
        (delete-file path)))))

(deftest devnet-cli-main-no-serve-prints-summary
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--port" "0"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (read-from-string (get-output-stream-string output))))
      (is (= 1337 (getf summary :chain-id)))
      (is (= 0 (getf summary :head-number)))
      (is (string= "127.0.0.1:8545" (getf summary :rpc-endpoint)))
      (is (getf summary :state-available-p)))))

(deftest devnet-cli-main-kzg-verifier-command-scopes-hooks
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream))
        (missing-output (make-string-output-stream))
        (missing-errors (make-string-output-stream))
        (non-executable-output (make-string-output-stream))
        (non-executable-errors (make-string-output-stream))
        (kzg-command
          (devnet-cli-temp-path "ethereum-lisp-kzg-scoped" "sh"))
        (missing-kzg-command
          (devnet-cli-temp-path "ethereum-lisp-kzg-missing" "sh"))
        (non-executable-kzg-command
          (devnet-cli-temp-path "ethereum-lisp-kzg-non-executable" "sh"))
        (old-point-verifier *kzg-point-proof-verifier*)
        (old-blob-verifier *kzg-blob-proof-verifier*))
    (unwind-protect
         (progn
           (setf *kzg-point-proof-verifier* nil
                 *kzg-blob-proof-verifier* nil)
           (devnet-cli-write-temp-file
            kzg-command
            "#!/bin/sh\necho true\n")
           (devnet-cli-make-executable kzg-command)
           (devnet-cli-write-temp-file
            non-executable-kzg-command
            "#!/bin/sh\necho true\n")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--kzg-verifier-command" (namestring kzg-command)
                         "--kzg-verifier-timeout" "2"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (string= (namestring kzg-command)
                          (fixture-object-field
                           summary "kzgVerifierCommand")))
             (is (= 2 (fixture-object-field
                       summary "kzgVerifierTimeoutSeconds")))
             (is (fixture-object-field
                  summary "kzgProofVerificationAvailable")))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--kzg-verifier-command"
                         (namestring missing-kzg-command)
                         "--json"
                         "--no-serve")
                   :output-stream missing-output
                   :error-stream missing-errors)))
           (is (string= "" (get-output-stream-string missing-output)))
           (is (search "KZG verifier command is not executable"
                       (get-output-stream-string missing-errors)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--kzg-verifier-command"
                         (namestring non-executable-kzg-command)
                         "--json"
                         "--no-serve")
                   :output-stream non-executable-output
                   :error-stream non-executable-errors)))
           (is (string= ""
                        (get-output-stream-string non-executable-output)))
           (is (search "KZG verifier command is not executable"
                       (get-output-stream-string non-executable-errors)))
           (is (not (kzg-proof-verification-available-p))))
      (setf *kzg-point-proof-verifier* old-point-verifier
            *kzg-blob-proof-verifier* old-blob-verifier)
      (when (probe-file kzg-command)
        (delete-file kzg-command))
      (when (probe-file missing-kzg-command)
        (delete-file missing-kzg-command))
      (when (probe-file non-executable-kzg-command)
        (delete-file non-executable-kzg-command)))))

(deftest ethereum-lisp-script-engine-only-kzg-verifier-advertises-blob-capabilities
  #-sbcl
  (skip-test "Ethereum Lisp process script requires SBCL")
  #+sbcl
  (let* ((script (namestring (truename "scripts/ethereum-lisp.lisp")))
         (genesis (namestring (truename +devnet-cli-genesis-fixture+)))
         (kzg-command
           (devnet-cli-temp-path "ethereum-lisp-script-kzg-command" "sh"))
         (ready-path
           (devnet-cli-temp-path "ethereum-lisp-script-kzg-ready" "json"))
         (log-path
           (devnet-cli-temp-path "ethereum-lisp-script-kzg" "log"))
         (pid-path
           (devnet-cli-temp-path "ethereum-lisp-script-kzg" "pid"))
         (process nil))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            kzg-command
            "#!/bin/sh\necho true\n")
           (devnet-cli-make-executable kzg-command)
           (setf process
                 (uiop:launch-program
                  (list "sbcl"
                        "--script"
                        script
                        "--"
                        "devnet"
                        "--genesis"
                        genesis
                        "--authrpc.addr"
                        "127.0.0.1"
                        "--authrpc.port"
                        "0"
                        "--http=false"
                        "--kzg.verifier-command"
                        (namestring kzg-command)
                        "--kzg.verifier-timeout"
                        "2"
                        "--ready-file"
                        (namestring ready-path)
                        "--log-file"
                        (namestring log-path)
                        "--pid-file"
                        (namestring pid-path)
                        "--max-connections"
                        "1"
                        "--json")
                  :directory #P"/private/tmp/"
                  :output :stream
                  :error-output :stream))
           (unless (devnet-cli-wait-for-file ready-path 10)
             (when (uiop:process-alive-p process)
               (uiop:terminate-process process)
               (devnet-cli-wait-process-exit process 5))
             (let ((stdout
                     (devnet-cli-read-stream-string
                      (uiop:process-info-output process)))
                   (stderr
                     (devnet-cli-read-stream-string
                      (uiop:process-info-error-output process))))
               (when (search "Operation not permitted" stderr)
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))
               (is (probe-file ready-path))
               (is (string= "" stdout))
               (is (string= "" stderr))))
           (when (probe-file ready-path)
             (let* ((ready-summary
                      (parse-json (devnet-cli-file-string ready-path)))
                    (pid (devnet-cli-pid-file-process-id pid-path))
                    (engine-endpoint
                      (fixture-object-field ready-summary "engineEndpoint"))
                    (capabilities-body
                      "{\"jsonrpc\":\"2.0\",\"id\":715,\"method\":\"engine_exchangeCapabilities\",\"params\":[[]]}")
                    capabilities-response)
               (is (= pid (fixture-object-field ready-summary "processId")))
               (is (stringp engine-endpoint))
               (is (not (fixture-object-field ready-summary "rpcEndpoint")))
               (is (not (fixture-object-field ready-summary
                                               "publicRpcEnabled")))
               (is (string= (namestring kzg-command)
                            (fixture-object-field ready-summary
                                                  "kzgVerifierCommand")))
               (is (= 2 (fixture-object-field
                         ready-summary "kzgVerifierTimeoutSeconds")))
               (is (fixture-object-field
                    ready-summary "kzgProofVerificationAvailable"))
               (handler-case
                   (setf capabilities-response
                         (devnet-cli-http-endpoint-request
                          engine-endpoint
                          (devnet-cli-json-rpc-http-request
                           capabilities-body)))
                 (sb-bsd-sockets:operation-not-permitted-error ()
                   (skip-test
                    "Local socket connect is not permitted in this sandbox")))
               (is (= 200 (devnet-cli-http-status capabilities-response)))
               (let* ((capabilities-rpc
                        (parse-json
                         (devnet-cli-http-body capabilities-response)))
                      (capabilities-result
                        (fixture-object-field capabilities-rpc "result")))
                 (is (= 715 (fixture-object-field capabilities-rpc "id")))
                 (devnet-cli-assert-kzg-backed-engine-capability-list
                  capabilities-result))
               (let ((status (devnet-cli-wait-process-exit process 10)))
                 (when (eq status :timeout)
                   (uiop:terminate-process process))
                 (is (not (eq status :timeout)))
                 (is (and (numberp status) (= 0 status)))
                 (let ((stdout
                         (devnet-cli-read-stream-string
                          (uiop:process-info-output process)))
                       (stderr
                         (devnet-cli-read-stream-string
                          (uiop:process-info-error-output process))))
                   (is (string= "" stderr))
                   (when (and (numberp status) (= 0 status))
                     (let* ((stdout-summary (parse-json stdout))
                            (log-records (devnet-cli-file-forms log-path))
                            (ready-record
                              (find "devnet.ready" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name))))
                            (shutdown-record
                              (find "devnet.shutdown" log-records
                                    :test #'string=
                                    :key (lambda (record)
                                           (getf record :name)))))
                       (dolist (summary (list stdout-summary ready-summary))
                         (is (string= (namestring kzg-command)
                                      (fixture-object-field
                                       summary "kzgVerifierCommand")))
                         (is (= 2 (fixture-object-field
                                   summary
                                   "kzgVerifierTimeoutSeconds")))
                         (is (fixture-object-field
                              summary
                              "kzgProofVerificationAvailable")))
                       (dolist (record (list ready-record shutdown-record))
                         (is record)
                         (let ((fields (getf record :fields)))
                           (is (string= (namestring kzg-command)
                                        (cdr (assoc "kzgVerifierCommand"
                                                    fields
                                                    :test #'string=))))
                           (is (string= "2"
                                        (cdr (assoc
                                              "kzgVerifierTimeoutSeconds"
                                              fields
                                              :test #'string=))))
                           (is (string= "true"
                                        (cdr (assoc
                                              "kzgProofVerificationAvailable"
                                              fields
                                              :test #'string=))))))
                       (let ((shutdown-fields
                               (getf shutdown-record :fields)))
                         (is (string= "1"
                                      (cdr (assoc "engineConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "0"
                                      (cdr (assoc "publicConnections"
                                                  shutdown-fields
                                                  :test #'string=))))
                         (is (string= "1"
                                      (cdr (assoc "totalConnections"
                                                  shutdown-fields
                                                  :test #'string=)))))))))))
      (when (and process (uiop:process-alive-p process))
        (uiop:terminate-process process))
      (when (probe-file kzg-command)
        (delete-file kzg-command))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path))))))

(deftest devnet-cli-main-database-restores-and-exports-chain-store
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-chain" "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (let* ((seed-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0))
                  (seed-store
                    (ethereum-lisp.cli:devnet-node-store seed-node))
                  (genesis
                    (ethereum-lisp.cli:devnet-node-genesis-block seed-node))
                  (funded
                    (address-from-hex
                     "0x0000000000000000000000000000000000001001"))
                  (child
                    (make-block
                     :header
                     (make-block-header
                      :number 1
                      :parent-hash (block-hash genesis)
                      :timestamp 1
                      :gas-limit 30000000))))
             (let ((state (make-state-db)))
               (state-db-set-account
                state funded (make-state-account :balance 42))
               (setf (block-header-state-root (block-header child))
                     (state-db-root state)))
             (chain-store-put-block seed-store child :state-available-p t)
             (chain-store-put-account-balance
              seed-store (block-hash child) funded 42)
             (chain-store-set-canonical-head seed-store (block-hash child))
             (chain-store-export-to-kv
              seed-store
              (make-file-key-value-database database-path)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--engine-port" "0"
                         "--database" (namestring database-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((summary
                    (parse-json (get-output-stream-string output)))
                  (database
                    (make-file-key-value-database database-path))
                  (restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0
                     :database-path (namestring database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node))
                  (head
                    (chain-store-latest-block restored-store))
                  (funded
                    (address-from-hex
                     "0x0000000000000000000000000000000000001001")))
             (is (= 1337 (fixture-object-field summary "chainId")))
             (is (= 1 (fixture-object-field summary "headNumber")))
             (is (string= (namestring database-path)
                          (fixture-object-field summary "databasePath")))
             (is (< 0 (length (kv-chain-record-entries database :block))))
             (is (< 0 (length (kv-chain-record-entries
                               database :canonical-hash))))
             (is (= 1 (block-header-number (block-header head))))
             (is (chain-store-state-available-p restored-store
                                                (block-hash head)))
             (is (= 42
                    (chain-store-account-balance
                     restored-store (block-hash head) funded)))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-cli-main-datadir-defaults-database-path
  (let* ((datadir
           (devnet-cli-temp-directory "ethereum-lisp-devnet-datadir"))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (datadir-geth-jwt-path
           (merge-pathnames "geth/jwtsecret" datadir))
         (explicit-database-path
           (devnet-cli-temp-path "ethereum-lisp-devnet-explicit-chain" "sexp"))
         (explicit-jwt-path
           (devnet-cli-temp-path "ethereum-lisp-devnet-explicit-jwt" "hex"))
         (output (make-string-output-stream))
         (errors (make-string-output-stream))
         (override-output (make-string-output-stream))
         (override-errors (make-string-output-stream))
         (explicit-jwt-output (make-string-output-stream))
         (explicit-jwt-errors (make-string-output-stream))
         (geth-jwt-output (make-string-output-stream))
         (geth-jwt-errors (make-string-output-stream))
         (precommand-output (make-string-output-stream))
         (precommand-errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file datadir-jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file explicit-jwt-path +devnet-cli-jwt-secret+)
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--datadir" (namestring datadir)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((summary (parse-json (get-output-stream-string output)))
                  (database
                    (make-file-key-value-database datadir-database-path))
                  (restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0
                     :database-path (namestring datadir-database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node))
                  (head (chain-store-latest-block restored-store)))
             (is (string= (namestring datadir-database-path)
                          (fixture-object-field summary "databasePath")))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired"))
             (is (< 0 (length (kv-chain-record-entries database :block))))
             (is (< 0 (length (kv-chain-record-entries database :state))))
             (is (= 0 (block-header-number (block-header head))))
             (is (chain-store-state-available-p restored-store
                                                (block-hash head))))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--datadir" (namestring datadir)
                         "--database" (namestring explicit-database-path)
                         "--json"
                         "--no-serve")
                   :output-stream override-output
                   :error-stream override-errors)))
           (is (string= "" (get-output-stream-string override-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string override-output))))
             (is (string= (namestring explicit-database-path)
                          (fixture-object-field summary "databasePath"))))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--datadir" (namestring datadir)
                         "--jwt-secret" (namestring explicit-jwt-path)
                         "--json"
                         "--no-serve")
                   :output-stream explicit-jwt-output
                   :error-stream explicit-jwt-errors)))
           (is (string= "" (get-output-stream-string explicit-jwt-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string explicit-jwt-output))))
             (is (string= (namestring explicit-jwt-path)
                          (fixture-object-field summary "jwtSecretPath"))))
           (ensure-directories-exist datadir-geth-jwt-path)
           (devnet-cli-write-temp-file datadir-geth-jwt-path
                                       +devnet-cli-jwt-secret+)
           (delete-file datadir-jwt-path)
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--datadir" (namestring datadir)
                         "--json"
                         "--no-serve")
                   :output-stream geth-jwt-output
                   :error-stream geth-jwt-errors)))
           (is (string= "" (get-output-stream-string geth-jwt-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string geth-jwt-output))))
             (is (string= (namestring datadir-geth-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired")))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "--identity" "init"
                         "--datadir" (namestring datadir)
                         "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--json"
                         "--no-serve")
                   :output-stream precommand-output
                   :error-stream precommand-errors)))
           (is (string= "" (get-output-stream-string precommand-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string precommand-output))))
             (is (= 1337 (fixture-object-field summary "chainId")))
             (is (string= (namestring datadir-database-path)
                          (fixture-object-field summary "databasePath")))))
      (when (probe-file datadir-database-path)
        (delete-file datadir-database-path))
      (when (probe-file datadir-jwt-path)
        (delete-file datadir-jwt-path))
      (when (probe-file datadir-geth-jwt-path)
        (delete-file datadir-geth-jwt-path))
      (when (probe-file explicit-database-path)
        (delete-file explicit-database-path))
      (when (probe-file explicit-jwt-path)
        (delete-file explicit-jwt-path)))))

(deftest devnet-cli-main-init-datadir-seeds-genesis-and-database
  (let* ((datadir
           (devnet-cli-temp-directory "ethereum-lisp-devnet-init-datadir"))
         (datadir-genesis-path
           (merge-pathnames "genesis.json" datadir))
         (datadir-database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (datadir-jwt-path
           (merge-pathnames "jwtsecret" datadir))
         (explicit-jwt-path
           (devnet-cli-temp-path "ethereum-lisp-devnet-init-explicit-jwt"
                                 "hex"))
         (init-output (make-string-output-stream))
         (init-errors (make-string-output-stream))
         (devnet-output (make-string-output-stream))
         (devnet-errors (make-string-output-stream))
         (explicit-init-output (make-string-output-stream))
         (explicit-init-errors (make-string-output-stream))
         (explicit-devnet-output (make-string-output-stream))
         (explicit-devnet-errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "init"
                         "--datadir" (namestring datadir)
                         "--json"
                         +devnet-cli-genesis-fixture+)
                   :output-stream init-output
                   :error-stream init-errors)))
           (is (string= "" (get-output-stream-string init-errors)))
           (let* ((init-summary
                    (parse-json (get-output-stream-string init-output)))
                  (database
                    (make-file-key-value-database datadir-database-path)))
             (is (= 1337 (fixture-object-field init-summary "chainId")))
             (is (= 0 (fixture-object-field init-summary "headNumber")))
             (is (string= (namestring datadir-database-path)
                          (fixture-object-field init-summary "databasePath")))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field init-summary "jwtSecretPath")))
             (is (fixture-object-field init-summary "authRequired"))
             (is (probe-file datadir-genesis-path))
             (is (probe-file datadir-jwt-path))
             (is (= 32
                    (length
                     (hex-to-bytes
                      (string-trim '(#\Space #\Tab #\Newline #\Return)
                                   (devnet-cli-file-string
                                    datadir-jwt-path))))))
             (is (string= (devnet-cli-file-string
                           +devnet-cli-genesis-fixture+)
                          (devnet-cli-file-string datadir-genesis-path)))
             (is (< 0 (length (kv-chain-record-entries database :block))))
             (is (< 0 (length (kv-chain-record-entries database :state)))))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--datadir" (namestring datadir)
                         "--json"
                         "--no-serve")
                   :output-stream devnet-output
                   :error-stream devnet-errors)))
           (is (string= "" (get-output-stream-string devnet-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string devnet-output))))
             (is (= 1337 (fixture-object-field summary "chainId")))
             (is (= 0 (fixture-object-field summary "headNumber")))
             (is (string= (namestring (truename datadir-genesis-path))
                          (fixture-object-field summary "genesisPath")))
             (is (string= (namestring datadir-database-path)
                          (fixture-object-field summary "databasePath")))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired")))
           (devnet-cli-write-temp-file explicit-jwt-path +devnet-cli-jwt-secret+)
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "init"
                         "--datadir" (namestring datadir)
                         "--authrpc.jwtsecret" (namestring explicit-jwt-path)
                         "--json"
                         +devnet-cli-genesis-fixture+)
                   :output-stream explicit-init-output
                   :error-stream explicit-init-errors)))
           (is (string= "" (get-output-stream-string explicit-init-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string explicit-init-output))))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired"))
             (is (string= +devnet-cli-jwt-secret+
                          (string-trim
                           '(#\Space #\Tab #\Newline #\Return)
                           (devnet-cli-file-string datadir-jwt-path)))))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--datadir" (namestring datadir)
                         "--json"
                         "--no-serve")
                   :output-stream explicit-devnet-output
                   :error-stream explicit-devnet-errors)))
           (is (string= "" (get-output-stream-string explicit-devnet-errors)))
           (let ((summary (parse-json
                           (get-output-stream-string explicit-devnet-output))))
             (is (string= (namestring datadir-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (fixture-object-field summary "authRequired"))))
      (when (probe-file datadir-genesis-path)
        (delete-file datadir-genesis-path))
      (when (probe-file datadir-jwt-path)
        (delete-file datadir-jwt-path))
      (when (probe-file explicit-jwt-path)
        (delete-file explicit-jwt-path))
      (when (probe-file datadir-database-path)
        (delete-file datadir-database-path)))))

(deftest devnet-cli-main-dev-mode-uses-embedded-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet" "--dev" "--json" "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (= 1337 (fixture-object-field summary "chainId")))
      (is (= 0 (fixture-object-field summary "headNumber")))
      (is (= #x1c9c380
             (fixture-object-field summary "headGasLimit")))
      (is (fixture-field-present-p summary "genesisPath"))
      (is (null (fixture-object-field summary "genesisPath")))
      (is (eq t (fixture-object-field summary "devMode")))
      (is (eq t (fixture-object-field summary "stateAvailable"))))))

(deftest devnet-cli-main-dev-gaslimit-shapes-embedded-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--dev.gaslimit"
                  "31000000"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (eq t (fixture-object-field summary "devMode")))
      (is (= 31000000
             (fixture-object-field summary "headGasLimit"))))))

(deftest devnet-cli-main-miner-gaslimit-shapes-embedded-dev-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--miner.gaslimit"
                  "32000000"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (eq t (fixture-object-field summary "devMode")))
      (is (= 32000000
             (fixture-object-field summary "headGasLimit")))))
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--miner.gaslimit"
                  "32000000"
                  "--dev.gaslimit"
                  "33000000"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (= 33000000
             (fixture-object-field summary "headGasLimit"))))))

(deftest devnet-cli-main-miner-etherbase-shapes-dev-coinbase
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream))
        (coinbase "0x00000000000000000000000000000000000000cb"))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--miner.etherbase"
                  coinbase
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (eq t (fixture-object-field summary "devMode")))
      (is (string= coinbase
                   (fixture-object-field summary "coinbase")))))
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream))
        (coinbase "0x00000000000000000000000000000000000000cc"))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--dev"
                  "--miner.etherbase"
                  "0x00000000000000000000000000000000000000cb"
                  "--etherbase"
                  coinbase
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (string= coinbase
                   (fixture-object-field summary "coinbase"))))))

(deftest devnet-cli-main-treats-empty-database-as-new-chain
  (labels ((write-empty-kv-database (path)
             (with-open-file (stream path
                                     :direction :output
                                     :if-exists :supersede
                                     :if-does-not-exist :create)
               (let ((*print-readably* t)
                     (*print-pretty* nil))
                 (write '(:ethereum-lisp-kv-v1 nil) :stream stream)
                 (terpri stream)))))
    (dolist (mode '(:empty-file :empty-kv))
      (let ((database-path
              (devnet-cli-temp-path "ethereum-lisp-devnet-empty-chain"
                                     "sexp"))
            (output (make-string-output-stream))
            (errors (make-string-output-stream)))
        (unwind-protect
             (progn
               (ecase mode
                 (:empty-file
                  (devnet-cli-write-temp-file database-path ""))
                 (:empty-kv
                  (write-empty-kv-database database-path)))
               (is (= 0
                      (ethereum-lisp.cli:main
                       (list "devnet"
                             "--genesis" +devnet-cli-genesis-fixture+
                             "--port" "0"
                             "--database" (namestring database-path)
                             "--json"
                             "--no-serve")
                       :output-stream output
                       :error-stream errors)))
               (is (string= "" (get-output-stream-string errors)))
               (let* ((summary
                        (parse-json (get-output-stream-string output)))
                      (database (make-file-key-value-database database-path))
                      (restored-node
                        (ethereum-lisp.cli:make-devnet-node
                         :genesis-path +devnet-cli-genesis-fixture+
                         :port 0
                         :database-path (namestring database-path)))
                      (restored-store
                        (ethereum-lisp.cli:devnet-node-store restored-node))
                      (head (chain-store-latest-block restored-store)))
                 (is (= 1337 (fixture-object-field summary "chainId")))
                 (is (= 0 (fixture-object-field summary "headNumber")))
                 (is (eq t (fixture-object-field summary "stateAvailable")))
                 (is (< 0 (length (kv-chain-record-entries database :block))))
                 (is (< 0 (length (kv-chain-record-entries
                                   database :canonical-hash))))
                 (is (< 0 (length (kv-chain-record-entries database :state))))
                 (is (= 0 (block-header-number (block-header head))))
                 (is (chain-store-state-available-p restored-store
                                                    (block-hash head)))))
          (when (probe-file database-path)
            (delete-file database-path)))))))

(deftest devnet-cli-main-rejects-database-genesis-mismatch
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-mismatched-chain"
                                "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (let* ((seed-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0))
                  (seed-store
                    (ethereum-lisp.cli:devnet-node-store seed-node))
                  (state (make-state-db))
                  (mismatched-genesis
                    (make-block
                     :header
                     (make-block-header
                      :number 0
                      :timestamp 99
                      :gas-limit 30000000
                      :state-root (state-db-root state)))))
             (chain-store-put-block seed-store
                                    mismatched-genesis
                                    :state-available-p t)
             (commit-state-db-to-chain-store
              seed-store (block-hash mismatched-genesis) state)
             (chain-store-set-canonical-head seed-store
                                             (block-hash mismatched-genesis))
             (chain-store-export-to-kv
              seed-store
              (make-file-key-value-database database-path)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--database" (namestring database-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string output)))
           (is (search "Devnet database genesis does not match genesis file"
                       (get-output-stream-string errors))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-cli-main-prunes-state-before-database-export
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-pruned-chain" "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (let* ((seed-node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path +devnet-cli-genesis-fixture+
                   :port 0))
                (seed-store
                  (ethereum-lisp.cli:devnet-node-store seed-node))
                (genesis
                  (ethereum-lisp.cli:devnet-node-genesis-block seed-node))
                (funded
                  (address-from-hex
                   "0x0000000000000000000000000000000000001001"))
                (child
                  (make-block
                   :header
                   (make-block-header
                    :number 1
                    :parent-hash (block-hash genesis)
                    :timestamp 1
                    :gas-limit 30000000)))
                (genesis-id (hash32-bytes (block-hash genesis)))
                child-id)
           (let ((state (make-state-db)))
             (state-db-set-account
              state funded (make-state-account :balance 42))
             (setf (block-header-state-root (block-header child))
                   (state-db-root state)
                   child-id (hash32-bytes (block-hash child))))
           (chain-store-put-block seed-store child :state-available-p t)
           (chain-store-put-account-balance
            seed-store (block-hash child) funded 42)
           (chain-store-set-canonical-head seed-store (block-hash child))
           (chain-store-export-to-kv
            seed-store
            (make-file-key-value-database database-path))
           (let ((database (make-file-key-value-database database-path)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state genesis-id)
               (declare (ignore value))
               (is present-p)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--database" (namestring database-path)
                         "--prune-state-before" "2"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((summary (parse-json (get-output-stream-string output)))
                  (database (make-file-key-value-database database-path))
                  (restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path +devnet-cli-genesis-fixture+
                     :port 0
                     :database-path (namestring database-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node)))
             (is (= 1 (fixture-object-field summary "headNumber")))
             (is (eq t (fixture-object-field summary "stateAvailable")))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state genesis-id :missing)
               (is (eq :missing value))
               (is (not present-p)))
             (multiple-value-bind (value present-p)
                 (kv-get-chain-record database :state child-id)
               (declare (ignore value))
               (is present-p))
             (is (chain-store-known-block restored-store (block-hash genesis)))
             (is (not (chain-store-state-available-p
                       restored-store (block-hash genesis))))
             (is (chain-store-state-available-p
                  restored-store (block-hash child)))
             (is (= 42
                    (chain-store-account-balance
                     restored-store (block-hash child) funded)))))
      (when (probe-file database-path)
        (delete-file database-path)))))

(deftest devnet-cli-txpool-journal-persists-pending-transactions
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-journal" "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-genesis" "json")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json))
           (let* ((seed-node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path (namestring genesis-path)
                   :port 0
                   :txpool-journal-path (namestring journal-path)))
                (seed-store (ethereum-lisp.cli:devnet-node-store seed-node))
                (transaction
                  (devnet-cli-txpool-transaction
                   (ethereum-lisp.cli:devnet-node-config seed-node)
                   0
                   +devnet-cli-txpool-pending-gas-price+))
                (transaction-hash (transaction-hash transaction)))
           (ethereum-lisp.core::engine-payload-store-put-pending-transaction
            seed-store
            transaction)
           (ethereum-lisp.cli::devnet-node-export-database seed-node)
           (let ((journal (make-file-key-value-database journal-path)))
             (is (= 1 (length (kv-chain-record-entries journal :txpool)))))
           (let* ((restored-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :txpool-journal-path (namestring journal-path)))
                  (restored-store
                    (ethereum-lisp.cli:devnet-node-store restored-node))
                  (summary
                    (ethereum-lisp.cli:devnet-node-summary restored-node))
                  (summary-json
                    (ethereum-lisp.cli::devnet-node-summary-json-object
                     restored-node)))
             (is (string= (namestring journal-path)
                          (getf summary :txpool-journal-path)))
             (is (string= (namestring journal-path)
                          (cdr (assoc "txpoolJournalPath"
                                      summary-json
                                      :test #'string=))))
             (is (bytes= (transaction-encoding transaction)
                         (transaction-encoding
                          (ethereum-lisp.core::engine-payload-store-pending-transaction
                           restored-store
                           transaction-hash)))))))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-txpool-journal-coexists-with-database-restore
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-database" "sexp"))
        (journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-journal" "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-genesis" "json")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json))
           (let* ((seed-node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :database-path (namestring database-path)
                     :txpool-journal-path (namestring journal-path)))
                  (seed-store
                    (ethereum-lisp.cli:devnet-node-store seed-node))
                  (transaction
                    (devnet-cli-txpool-transaction
                     (ethereum-lisp.cli:devnet-node-config seed-node)
                     0
                     +devnet-cli-txpool-pending-gas-price+))
                  (transaction-hash (transaction-hash transaction)))
             (ethereum-lisp.core::engine-payload-store-put-pending-transaction
              seed-store
              transaction)
             (ethereum-lisp.cli::devnet-node-export-database seed-node)
             (is (= 1
                    (length
                     (kv-chain-record-entries
                      (make-file-key-value-database database-path)
                      :txpool))))
             (is (= 1
                    (length
                     (kv-chain-record-entries
                      (make-file-key-value-database journal-path)
                      :txpool))))
             (let* ((restored-node
                      (ethereum-lisp.cli:make-devnet-node
                       :genesis-path (namestring genesis-path)
                       :port 0
                       :database-path (namestring database-path)
                       :txpool-journal-path (namestring journal-path)))
                    (restored-store
                      (ethereum-lisp.cli:devnet-node-store restored-node)))
               (is (bytes= (transaction-encoding transaction)
                           (transaction-encoding
                            (ethereum-lisp.core::engine-payload-store-pending-transaction
                             restored-store
                             transaction-hash)))))))
      (when (probe-file database-path)
        (delete-file database-path))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-txpool-rejournal-refreshes-live-journal
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-rejournal"
                                "sexp"))
        (genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-genesis" "json"))
        (now 100))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path
            (devnet-cli-funded-txpool-genesis-json))
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path (namestring genesis-path)
                     :port 0
                     :txpool-journal-path (namestring journal-path)
                     :txpool-rejournal-seconds 10))
                  (state
                    (ethereum-lisp.cli::make-devnet-rejournal-state
                     node
                     10
                     :now-function (lambda () now)))
                  (transaction
                    (devnet-cli-txpool-transaction
                     (ethereum-lisp.cli:devnet-node-config node)
                     0
                     +devnet-cli-txpool-pending-gas-price+))
                  (telemetry-fields
                    (ethereum-lisp.cli::devnet-node-telemetry-fields node)))
             (is (string= "10"
                          (cdr (assoc "txpoolRejournalSeconds"
                                      telemetry-fields
                                      :test #'string=))))
             (ethereum-lisp.core::engine-payload-store-put-pending-transaction
              (ethereum-lisp.cli:devnet-node-store node)
              transaction)
             (setf now 109)
             (is (eq nil
                     (ethereum-lisp.cli::devnet-rejournal-state-tick state)))
             (is (not (probe-file journal-path)))
             (setf now 110)
             (is (eq t
                     (ethereum-lisp.cli::devnet-rejournal-state-tick state)))
             (let ((journal (make-file-key-value-database journal-path)))
               (is (= 1
                      (length
                       (kv-chain-record-entries journal :txpool)))))))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-txpool-rejournal-without-journal-is-noop
  (let ((unused-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-unused-rejournal"
                                "sexp"))
        (now 0))
    (unwind-protect
         (let* ((node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path +devnet-cli-genesis-fixture+
                   :port 0
                   :txpool-rejournal-seconds 1))
                (state
                  (ethereum-lisp.cli::make-devnet-rejournal-state
                   node
                   1
                   :now-function (lambda () now))))
           (setf now 1)
           (is (eq nil
                   (ethereum-lisp.cli::devnet-rejournal-state-tick state)))
           (is (not (probe-file unused-path))))
      (when (probe-file unused-path)
        (delete-file unused-path)))))

(deftest devnet-cli-dev-period-parses-and-reports-duration
  (let* ((options
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet"
                  "--dev"
                  "--dev.period=2m"
                  "--no-serve")))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path +devnet-cli-genesis-fixture+
            :port 0
            :dev-mode-p (getf options :dev-mode-p)
            :dev-period-seconds (getf options :dev-period-seconds)))
         (summary
           (ethereum-lisp.cli::devnet-node-summary-json-object node))
         (telemetry-fields
           (ethereum-lisp.cli::devnet-node-telemetry-fields node)))
    (is (= 120 (getf options :dev-period-seconds)))
    (is (= 120 (fixture-object-field summary "devPeriodSeconds")))
    (is (string= "120"
                 (cdr (assoc "devPeriodSeconds"
                             telemetry-fields
                             :test #'string=))))
    (signals error
      (ethereum-lisp.cli::devnet-cli-options
       (list "devnet" "--dev.period=-1" "--no-serve")))
    (signals error
      (ethereum-lisp.cli::devnet-cli-options
       (list "devnet" "--dev.period=bad" "--no-serve")))))

(deftest devnet-cli-dev-period-tick-seals-public-txpool-transaction
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json node)
             (parse-json
              (engine-rpc-handle-request-json
               json
               (ethereum-lisp.cli:devnet-node-store node)
               (ethereum-lisp.cli:devnet-node-config node)))))
    (let* ((now 0)
           (node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json (devnet-cli-funded-txpool-genesis-json)
              :port 0
              :dev-mode-p t
              :dev-period-seconds 1))
           (config (ethereum-lisp.cli:devnet-node-config node))
           (transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+))
           (transaction-hash
             (hash32-to-hex (transaction-hash transaction)))
           (raw-transaction (devnet-cli-transaction-raw transaction))
           (state
             (ethereum-lisp.cli::make-devnet-dev-period-state
              node
              1
              :now-function (lambda () now)))
           (send-response
             (request
              (concatenate
               'string
               "{\"jsonrpc\":\"2.0\",\"id\":1,"
               "\"method\":\"eth_sendRawTransaction\","
               "\"params\":[\"" raw-transaction "\"]}")
              node)))
      (is (string= transaction-hash (field send-response "result")))
      (is (eq nil (ethereum-lisp.cli::devnet-dev-period-state-tick state)))
      (setf now 1)
      (let* ((sealed-block
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (sealed-hash (hash32-to-hex (block-hash sealed-block)))
             (block-number-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"eth_blockNumber\",\"params\":[]}"
                node))
             (lookup-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":3,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" transaction-hash "\"]}")
                node))
             (receipt-response
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":4,"
                 "\"method\":\"eth_getTransactionReceipt\","
                 "\"params\":[\"" transaction-hash "\"]}")
                node))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                node))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"txpool_status\",\"params\":[]}"
                node))
             (mined-transaction (field lookup-response "result"))
             (receipt (field receipt-response "result"))
             (status (field status-response "result")))
        (is (typep sealed-block 'ethereum-block))
        (is (string= (quantity-to-hex 1)
                     (field block-number-response "result")))
        (is (string= transaction-hash
                     (field mined-transaction "hash")))
        (is (string= sealed-hash
                     (field mined-transaction "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field mined-transaction "blockNumber")))
        (is (string= (quantity-to-hex 0)
                     (field mined-transaction "transactionIndex")))
        (is (string= transaction-hash
                     (field receipt "transactionHash")))
        (is (string= sealed-hash (field receipt "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field receipt "blockNumber")))
        (is (string= (quantity-to-hex 0)
                     (field receipt "transactionIndex")))
        (is (= 0 (length (field pending-response "result"))))
        (is (string= (quantity-to-hex 0) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))))))

(deftest devnet-cli-dev-period-tick-bounds-transactions-by-gas-limit
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json node)
             (parse-json
              (engine-rpc-handle-request-json
               json
               (ethereum-lisp.cli:devnet-node-store node)
               (ethereum-lisp.cli:devnet-node-config node)))))
    (let* ((now 0)
           (node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json (devnet-cli-funded-txpool-genesis-json
                             :gas-limit 42000)
              :port 0
              :dev-mode-p t
              :dev-period-seconds 1))
           (config (ethereum-lisp.cli:devnet-node-config node))
           (first-transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+
              :gas-limit 21000))
           (second-transaction
             (devnet-cli-txpool-transaction
              config
              1
              +devnet-cli-txpool-pending-gas-price+
              :gas-limit 30000))
           (first-hash (hash32-to-hex (transaction-hash first-transaction)))
           (second-hash (hash32-to-hex
                         (transaction-hash second-transaction)))
           (state
             (ethereum-lisp.cli::make-devnet-dev-period-state
              node
              1
              :now-function (lambda () now))))
      (dolist (transaction (list first-transaction second-transaction))
        (request
         (concatenate
          'string
          "{\"jsonrpc\":\"2.0\",\"id\":1,"
          "\"method\":\"eth_sendRawTransaction\","
          "\"params\":[\""
          (devnet-cli-transaction-raw transaction)
          "\"]}")
         node))
      (setf now 1)
      (let* ((sealed-block
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (sealed-hash (hash32-to-hex (block-hash sealed-block)))
             (first-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":2,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" first-hash "\"]}")
                node))
             (second-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":3,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-hash "\"]}")
                node))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                node))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"txpool_status\",\"params\":[]}"
                node))
             (mined-transaction (field first-lookup "result"))
             (leftover-transaction (field second-lookup "result"))
             (pending-transactions (field pending-response "result"))
             (status (field status-response "result")))
        (is (typep sealed-block 'ethereum-block))
        (is (= 1 (length (block-transactions sealed-block))))
        (is (string= first-hash
                     (hash32-to-hex
                      (transaction-hash
                       (first (block-transactions sealed-block))))))
        (is (string= first-hash
                     (field mined-transaction "hash")))
        (is (string= sealed-hash
                     (field mined-transaction "blockHash")))
        (is (string= (quantity-to-hex 0)
                     (field mined-transaction "transactionIndex")))
        (is (string= second-hash
                     (field leftover-transaction "hash")))
        (is (null (field leftover-transaction "blockHash")))
        (is (= 1 (length pending-transactions)))
        (is (string= second-hash
                     (field (first pending-transactions) "hash")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))))))

(deftest devnet-cli-dev-period-tick-selects-fitting-second-sender
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (request (json node)
             (parse-json
              (engine-rpc-handle-request-json
               json
               (ethereum-lisp.cli:devnet-node-store node)
               (ethereum-lisp.cli:devnet-node-config node)))))
    (let* ((now 0)
           (first-private-key 2)
           (second-private-key +devnet-cli-txpool-private-key+)
           (node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json (devnet-cli-funded-txpool-genesis-json
                             :gas-limit 42000
                             :private-keys (list first-private-key
                                                 second-private-key))
              :port 0
              :dev-mode-p t
              :dev-period-seconds 1))
           (config (ethereum-lisp.cli:devnet-node-config node))
           (first-sender-fitting-transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+
              :private-key first-private-key
              :gas-limit 21000))
           (first-sender-non-fitting-transaction
             (devnet-cli-txpool-transaction
              config
              1
              +devnet-cli-txpool-pending-gas-price+
              :private-key first-private-key
              :gas-limit 30000))
           (second-sender-fitting-transaction
             (devnet-cli-txpool-transaction
              config
              0
              +devnet-cli-txpool-pending-gas-price+
              :private-key second-private-key
              :gas-limit 21000))
           (first-fitting-hash
             (hash32-to-hex
              (transaction-hash first-sender-fitting-transaction)))
           (first-non-fitting-hash
             (hash32-to-hex
              (transaction-hash first-sender-non-fitting-transaction)))
           (second-fitting-hash
             (hash32-to-hex
              (transaction-hash second-sender-fitting-transaction)))
           (state
             (ethereum-lisp.cli::make-devnet-dev-period-state
              node
              1
              :now-function (lambda () now))))
      (dolist (transaction
               (list first-sender-fitting-transaction
                     first-sender-non-fitting-transaction
                     second-sender-fitting-transaction))
        (request
         (concatenate
          'string
          "{\"jsonrpc\":\"2.0\",\"id\":1,"
          "\"method\":\"eth_sendRawTransaction\","
          "\"params\":[\""
          (devnet-cli-transaction-raw transaction)
          "\"]}")
         node))
      (setf now 1)
      (let* ((sealed-block
               (ethereum-lisp.cli::devnet-dev-period-state-tick state))
             (sealed-hash (hash32-to-hex (block-hash sealed-block)))
             (mined-hashes
               (mapcar
                (lambda (transaction)
                  (hash32-to-hex (transaction-hash transaction)))
                (block-transactions sealed-block)))
             (second-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":2,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" second-fitting-hash "\"]}")
                node))
             (second-receipt
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":3,"
                 "\"method\":\"eth_getTransactionReceipt\","
                 "\"params\":[\"" second-fitting-hash "\"]}")
                node))
             (leftover-lookup
               (request
                (concatenate
                 'string
                 "{\"jsonrpc\":\"2.0\",\"id\":4,"
                 "\"method\":\"eth_getTransactionByHash\","
                 "\"params\":[\"" first-non-fitting-hash "\"]}")
                node))
             (pending-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"eth_pendingTransactions\",\"params\":[]}"
                node))
             (status-response
               (request
                "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"txpool_status\",\"params\":[]}"
                node))
             (second-mined-transaction (field second-lookup "result"))
             (second-mined-receipt (field second-receipt "result"))
             (leftover-transaction (field leftover-lookup "result"))
             (pending-transactions (field pending-response "result"))
             (status (field status-response "result")))
        (is (typep sealed-block 'ethereum-block))
        (is (equal (list first-fitting-hash second-fitting-hash)
                   mined-hashes))
        (is (string= second-fitting-hash
                     (field second-mined-transaction "hash")))
        (is (string= sealed-hash
                     (field second-mined-transaction "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field second-mined-transaction "transactionIndex")))
        (is (string= second-fitting-hash
                     (field second-mined-receipt "transactionHash")))
        (is (string= sealed-hash
                     (field second-mined-receipt "blockHash")))
        (is (string= (quantity-to-hex 1)
                     (field second-mined-receipt "transactionIndex")))
        (is (string= first-non-fitting-hash
                     (field leftover-transaction "hash")))
        (is (null (field leftover-transaction "blockHash")))
        (is (= 1 (length pending-transactions)))
        (is (string= first-non-fitting-hash
                     (field (first pending-transactions) "hash")))
        (is (string= (quantity-to-hex 1) (field status "pending")))
        (is (string= (quantity-to-hex 0) (field status "queued")))))))

(deftest devnet-cli-dev-period-tick-carries-active-fork-bodies
  (let* ((now 0)
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json
            (devnet-cli-funded-txpool-genesis-json
             :config-fields
             (list (cons "cancunTime" "0x0")
                   (cons "pragueTime" "0x0")
                   (cons "amsterdamTime" "0x0")))
            :port 0
            :dev-mode-p t
            :dev-period-seconds 1))
         (config (ethereum-lisp.cli:devnet-node-config node))
         (transaction
           (devnet-cli-txpool-transaction
            config
            0
            +devnet-cli-txpool-pending-gas-price+))
         (state
           (ethereum-lisp.cli::make-devnet-dev-period-state
            node
            1
            :now-function (lambda () now))))
    (engine-rpc-handle-request-json
     (concatenate
      'string
      "{\"jsonrpc\":\"2.0\",\"id\":1,"
      "\"method\":\"eth_sendRawTransaction\","
      "\"params\":[\"" (devnet-cli-transaction-raw transaction) "\"]}")
     (ethereum-lisp.cli:devnet-node-store node)
     config)
    (setf now 1)
    (let* ((block
             (ethereum-lisp.cli::devnet-dev-period-state-tick state))
           (header (block-header block)))
      (is (typep block 'ethereum-block))
      (is (= 1 (length (block-transactions block))))
      (is (= 0 (block-header-blob-gas-used header)))
      (is (= 0 (block-header-excess-blob-gas header)))
      (is (string= (hash32-to-hex (zero-hash32))
                   (hash32-to-hex
                    (block-header-parent-beacon-root header))))
      (is (block-requests-present-p block))
      (is (null (block-requests block)))
      (is (string= (hash32-to-hex (execution-requests-hash '()))
                   (hash32-to-hex
                    (block-header-requests-hash header))))
      (is (block-block-access-list-present-p block))
      (is (null (block-block-access-list block)))
      (is (string= (hash32-to-hex (block-access-list-hash '()))
                   (hash32-to-hex
                    (block-header-block-access-list-hash header)))))))

(deftest devnet-cli-txpool-journal-rejects-wrong-chain-transactions
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-txpool-bad-chain"
                                "sexp")))
    (unwind-protect
         (let* ((config
                  (chain-config-from-genesis-json-file
                   +devnet-cli-genesis-fixture+))
                (transaction
                  (fixture-sign-legacy-transaction
                   (make-legacy-transaction
                    :nonce 0
                    :gas-price +devnet-cli-txpool-gas-price+
                    :gas-limit +devnet-cli-txpool-gas-limit+
                    :to (address-from-hex +devnet-cli-txpool-recipient+)
                    :value +devnet-cli-txpool-value+)
                   +devnet-cli-txpool-private-key+
                   (1+ (chain-config-chain-id config))))
                (journal (make-file-key-value-database journal-path)))
           (kv-put-chain-record
            journal
            :txpool
            (hash32-bytes (transaction-hash transaction))
            (ethereum-lisp.core::chain-store-txpool-transaction-record-rlp
             :pending
             transaction))
           (signals block-validation-error
             (ethereum-lisp.cli:make-devnet-node
              :genesis-path +devnet-cli-genesis-fixture+
              :port 0
              :txpool-journal-path (namestring journal-path))))
      (when (probe-file journal-path)
        (delete-file journal-path)))))

(deftest devnet-cli-main-json-summary-and-ready-file
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex"))
        (ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (pid-path (devnet-cli-temp-path "ethereum-lisp-devnet" "pid"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file ready-path "stale readiness")
           (devnet-cli-write-temp-file pid-path "0")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--engine-port" "0"
                         "--public-port" "8546"
                         "--jwt-secret" (namestring jwt-path)
                         "--txpool.rejournal" "2m"
                         "--ready-file" (namestring ready-path)
                         "--pid-file" (namestring pid-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path))))
             (is (= (devnet-cli-current-process-id)
                    (devnet-cli-pid-file-process-id pid-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (= 1337 (fixture-object-field summary "chainId")))
               (is (= 0 (fixture-object-field summary "headNumber")))
               (is (null (fixture-object-field summary "safeNumber")))
               (is (null (fixture-object-field summary "safeHash")))
               (is (null (fixture-object-field summary "finalizedNumber")))
               (is (null (fixture-object-field summary "finalizedHash")))
               (is (string= "127.0.0.1:0"
                            (fixture-object-field summary "engineEndpoint")))
               (is (string= "127.0.0.1:8546"
                            (fixture-object-field summary "rpcEndpoint")))
               (is (equal (devnet-cli-current-process-id)
                          (fixture-object-field summary "processId")))
               (is (string= (namestring pid-path)
                            (fixture-object-field summary "pidFilePath")))
               (is (eq t (fixture-object-field summary "authRequired")))
               (is (= 120
                      (fixture-object-field summary "txpoolRejournalSeconds")))
               (is (eq t (fixture-object-field summary "stateAvailable")))
               (is (string= (namestring jwt-path)
                            (fixture-object-field summary "jwtSecretPath"))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest devnet-cli-main-creates-artifact-parent-directories
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-artifact-parents"))
         (ready-path
           (merge-pathnames "ready/nested/devnet-ready.json" root))
         (log-path
           (merge-pathnames "logs/nested/devnet.log" root))
         (pid-path
           (merge-pathnames "pid/nested/devnet.pid" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--ready-file" (namestring ready-path)
                         "--log-file" (namestring log-path)
                         "--pid-file" (namestring pid-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path)))
             (is (= (devnet-cli-current-process-id)
                    (devnet-cli-pid-file-process-id pid-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= (namestring log-path)
                            (fixture-object-field summary "logPath")))
               (is (string= (namestring pid-path)
                            (fixture-object-field summary "pidFilePath"))))
             (is (= 2 (length log-records)))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest devnet-cli-main-accepts-explicit-engine-endpoint-options
  (let ((ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (log-path (devnet-cli-temp-path "ethereum-lisp-devnet" "log"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--engine-host" "192.0.2.10"
                         "--engine-port" "9551"
                         "--public-host" "192.0.2.11"
                         "--public-port" "9545"
                         "--ready-file" (namestring ready-path)
                         "--log-file" (namestring log-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= "192.0.2.10:9551"
                            (fixture-object-field summary "engineEndpoint")))
               (is (string= "192.0.2.11:9545"
                            (fixture-object-field summary "rpcEndpoint"))))
             (dolist (log-record log-records)
               (let ((fields (getf log-record :fields)))
                 (is (string= "192.0.2.10:9551"
                              (cdr (assoc "engineEndpoint" fields
                                          :test #'string=))))
                 (is (string= "192.0.2.11:9545"
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path)))))

(deftest devnet-cli-main-accepts-geth-style-runner-aliases
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex"))
        (config-path (devnet-cli-temp-path "ethereum-lisp-devnet-geth" "toml"))
        (ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (log-path (devnet-cli-temp-path "ethereum-lisp-devnet" "log"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (with-open-file (stream jwt-path
                                   :direction :output
                                   :if-exists :supersede
                                   :if-does-not-exist :create)
             (write-string
             "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
             stream))
           (devnet-cli-write-temp-file
            config-path
            "# geth runner config intentionally empty for alias coverage\n")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         (format nil "--config=~A" (namestring config-path))
                         (format nil "--genesis=~A"
                                 +devnet-cli-genesis-fixture+)
                         "--authrpc.addr=192.0.2.30"
                         "--authrpc.port=9651"
                         (format nil "--authrpc.jwtsecret=~A"
                                 (namestring jwt-path))
                         "--authrpc.rpcprefix=/engine"
                         "--authrpc.vhosts=engine.runner,localhost"
                         "--authrpc.corsdomain=https://engine.runner"
                         "--http=false"
                         "--http.addr=192.0.2.31"
                         "--http.port=9645"
                         "--http.api=eth,net,web3,txpool"
                         "--http.rpcprefix=/rpc"
                         "--http.vhosts=public.runner,localhost"
                         "--http.corsdomain=https://runner.example,*"
                         "--ws=false"
                         "--ws.addr=192.0.2.32"
                         "--ws.port=9646"
                         "--ws.api=eth,net"
                         "--ws.origins=*"
                         "--ws.rpcprefix=/ws"
                         "--ipcapi=eth,net,web3"
                         "--graphql=false"
                         "--graphql.addr=192.0.2.33"
                         "--graphql.port=9647"
                         "--graphql.vhosts=*"
                         "--graphql.corsdomain=*"
                         "--networkid=7331"
                         "--mainnet=false"
                         "--sepolia=false"
                         "--holesky=false"
                         "--hoodi=false"
                         "--goerli=false"
                         "--syncmode=full"
                         "--nodiscover=false"
                         "--ipcdisable=true"
                         "--verbosity=3"
                         "--maxpeers=0"
                         "--nat=none"
                         "--netrestrict=127.0.0.0/8"
                         "--identity=ethereum-lisp-devnet"
                         "--nodekey=/tmp/ethereum-lisp-nodekey"
                         "--nodekeyhex=010203"
                         "--discovery.port=30303"
                         "--discovery.dns="
                         "--ipcpath=/tmp/ethereum-lisp.ipc"
                         "--allow-insecure-unlock=false"
                         (format nil "--ready-file=~A"
                                 (namestring ready-path))
                         (format nil "--log-file=~A"
                                 (namestring log-path))
                         "--json=true"
                         "--no-serve=1")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= "192.0.2.30:9651"
                            (fixture-object-field summary "engineEndpoint")))
               (is (not (fixture-object-field summary "rpcEndpoint")))
               (is (not (fixture-object-field summary "publicRpcEnabled")))
               (is (string= "/engine"
                            (fixture-object-field summary
                                                  "engineRpcPrefix")))
               (is (string= "/rpc"
                            (fixture-object-field summary
                                                  "publicRpcPrefix")))
               (is (= 7331 (fixture-object-field summary "networkId")))
               (is (eq t (fixture-object-field summary "authRequired")))
               (is (string= (namestring jwt-path)
                            (fixture-object-field summary "jwtSecretPath")))
               (is (equal '("eth" "net" "web3" "txpool")
                          (fixture-object-field summary
                                                "publicApiModules")))
               (is (equal '("https://engine.runner")
                          (fixture-object-field summary
                                                "engineCorsOrigins")))
               (is (equal '("https://runner.example" "*")
                          (fixture-object-field summary
                                                "publicCorsOrigins")))
               (is (equal '("engine.runner" "localhost")
                          (fixture-object-field summary "engineVhosts")))
               (is (equal '("public.runner" "localhost")
                          (fixture-object-field summary "publicVhosts"))))
             (dolist (log-record log-records)
               (let ((fields (getf log-record :fields)))
                 (is (string= "0x1ca3"
                              (cdr (assoc "networkId" fields
                                          :test #'string=))))
                 (is (string= "/engine"
                              (cdr (assoc "engineRpcPrefix" fields
                                          :test #'string=))))
                 (is (string= "/rpc"
                              (cdr (assoc "publicRpcPrefix" fields
                                          :test #'string=))))
                 (is (string= ""
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))
                 (is (string= "false"
                              (cdr (assoc "publicRpcEnabled" fields
                                          :test #'string=))))
                 (is (string= "eth,net,web3,txpool"
                              (cdr (assoc "publicApiModules" fields
                                          :test #'string=))))
                 (is (string= "https://engine.runner"
                              (cdr (assoc "engineCorsOrigins" fields
                                          :test #'string=))))
                 (is (string= "https://runner.example,*"
                              (cdr (assoc "publicCorsOrigins" fields
                                          :test #'string=))))
                 (is (string= "engine.runner,localhost"
                              (cdr (assoc "engineVhosts" fields
                                          :test #'string=))))
                 (is (string= "public.runner,localhost"
                              (cdr (assoc "publicVhosts" fields
                                          :test #'string=))))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-applies-geth-config-file-values
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-config"))
         (datadir (merge-pathnames "datadir/" root))
         (database-path
           (merge-pathnames "ethereum-lisp-chain.sexp" datadir))
         (jwt-path (merge-pathnames "jwt.hex" root))
         (config-path (merge-pathnames "geth.toml" root))
         (journal-path (merge-pathnames "txpool-journal.sexp" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist datadir)
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file
            config-path
            (format nil
                    "[Eth]~%NetworkId = 4242~%~
                     [Eth.TxPool]~%PriceLimit = 7~%PriceBump = 25~%~
                     AccountSlots = 3~%GlobalSlots = 4~%~
                     AccountQueue = 9~%GlobalQueue = 12~%~
                     Lifetime = \"3h0m0s\"~%~
                     Journal = ~S~%~
                     Rejournal = \"45m\"~%~
                     Locals = [\"0x0000000000000000000000000000000000000001\", ~
                     \"0x0000000000000000000000000000000000000002\"]~%~
                     NoLocals = true~%~
                     [Node]~%DataDir = ~S~%~
                     HTTPHost = \"192.0.2.41\"~%HTTPPort = 1945~%~
                     HTTPModules = [\"eth\", \"net\"]~%~
                     HTTPCors = [\"https://public.example\", \"*\"]~%~
                     HTTPVirtualHosts = [\"public.example\", \"localhost\"]~%~
                     HTTPPathPrefix = \"/rpc\"~%~
                     AuthAddr = \"192.0.2.42\"~%AuthPort = 1951~%~
                     AuthVirtualHosts = [\"engine.example\", \"localhost\"]~%~
                     JWTSecret = ~S~%"
                    (namestring journal-path)
                    (namestring datadir)
                    (namestring jwt-path)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (string= "192.0.2.42:1951"
                          (fixture-object-field summary "engineEndpoint")))
             (is (string= "192.0.2.41:1945"
                          (fixture-object-field summary "rpcEndpoint")))
             (is (= 4242 (fixture-object-field summary "networkId")))
             (is (= 7 (fixture-object-field summary "txpoolPriceLimit")))
             (is (= 25 (fixture-object-field summary "txpoolPriceBump")))
             (is (= 3 (fixture-object-field summary "txpoolAccountSlots")))
             (is (= 4 (fixture-object-field summary "txpoolGlobalSlots")))
             (is (= 9 (fixture-object-field summary "txpoolAccountQueue")))
             (is (= 12 (fixture-object-field summary "txpoolGlobalQueue")))
             (is (= 10800
                    (fixture-object-field summary "txpoolLifetimeSeconds")))
             (is (string= (namestring journal-path)
                          (fixture-object-field summary
                                                "txpoolJournalPath")))
             (is (= 2700
                    (fixture-object-field summary "txpoolRejournalSeconds")))
             (is (equal '("0x0000000000000000000000000000000000000001"
                          "0x0000000000000000000000000000000000000002")
                        (fixture-object-field summary "txpoolLocals")))
             (is (eq t (fixture-object-field summary "txpoolNoLocals")))
             (is (string= "/rpc"
                          (fixture-object-field summary "publicRpcPrefix")))
             (is (string= (namestring jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))
             (is (eq t (fixture-object-field summary "authRequired")))
             (is (string= (namestring database-path)
                          (fixture-object-field summary "databasePath")))
             (is (equal '("eth" "net")
                        (fixture-object-field summary "publicApiModules")))
             (is (equal '("https://public.example" "*")
                        (fixture-object-field summary "publicCorsOrigins")))
             (is (equal '("public.example" "localhost")
                        (fixture-object-field summary "publicVhosts")))
             (is (equal '("engine.example" "localhost")
                        (fixture-object-field summary "engineVhosts")))))
      (when (probe-file database-path)
        (delete-file database-path))
      (when (probe-file journal-path)
        (delete-file journal-path))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-explicit-options-override-geth-config-file
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-config-override"))
         (jwt-path (merge-pathnames "config-jwt.hex" root))
         (override-jwt-path (merge-pathnames "override-jwt.hex" root))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (devnet-cli-write-temp-file
            override-jwt-path
            "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")
           (devnet-cli-write-temp-file
            config-path
            (format nil
                    "[Eth]~%NetworkId = 4242~%~
                     [Eth.TxPool]~%PriceLimit = 7~%PriceBump = 25~%~
                     AccountSlots = 3~%GlobalSlots = 4~%~
                     AccountQueue = 9~%GlobalQueue = 12~%~
                     Lifetime = \"3h0m0s\"~%~
                     Rejournal = \"3h0m0s\"~%~
                     Locals = [\"0x0000000000000000000000000000000000000001\"]~%~
                     NoLocals = true~%~
                     [Node]~%HTTPHost = \"192.0.2.50\"~%HTTPPort = 1950~%~
                     AuthAddr = \"192.0.2.51\"~%AuthPort = 1951~%~
                     JWTSecret = ~S~%"
                    (namestring jwt-path)))
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--authrpc.addr" "192.0.2.60"
                         "--authrpc.port" "1960"
                         "--http.addr" "192.0.2.61"
                         "--http.port" "1961"
                         "--networkid" "7331"
                         "--txpool.pricelimit" "11"
                         "--txpool.pricebump" "40"
                         "--txpool.accountslots" "5"
                         "--txpool.globalslots" "6"
                         "--txpool.accountqueue" "10"
                         "--txpool.globalqueue" "20"
                         "--txpool.lifetime" "1h2m3s"
                         "--txpool.rejournal" "10m"
                         "--txpool.locals"
                         "0x0000000000000000000000000000000000000002"
                         "--txpool.nolocals" "false"
                         "--authrpc.jwtsecret" (namestring override-jwt-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (string= "192.0.2.60:1960"
                          (fixture-object-field summary "engineEndpoint")))
             (is (string= "192.0.2.61:1961"
                          (fixture-object-field summary "rpcEndpoint")))
             (is (= 7331 (fixture-object-field summary "networkId")))
             (is (= 11 (fixture-object-field summary "txpoolPriceLimit")))
             (is (= 40 (fixture-object-field summary "txpoolPriceBump")))
             (is (= 5 (fixture-object-field summary "txpoolAccountSlots")))
             (is (= 6 (fixture-object-field summary "txpoolGlobalSlots")))
             (is (= 10 (fixture-object-field summary "txpoolAccountQueue")))
             (is (= 20 (fixture-object-field summary "txpoolGlobalQueue")))
             (is (= 3723
                    (fixture-object-field summary "txpoolLifetimeSeconds")))
             (is (= 600
                    (fixture-object-field summary "txpoolRejournalSeconds")))
             (is (equal '("0x0000000000000000000000000000000000000002")
                        (fixture-object-field summary "txpoolLocals")))
             (is (eq nil (fixture-object-field summary "txpoolNoLocals")))
             (is (string= (namestring override-jwt-path)
                          (fixture-object-field summary "jwtSecretPath")))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file override-jwt-path)
        (delete-file override-jwt-path))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-applies-geth-miner-config-file-values
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-miner-config"))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file
            config-path
            "[Eth.Miner]
GasCeil = 34000000
")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--dev"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (eq t (fixture-object-field summary "devMode")))
             (is (= 34000000
                    (fixture-object-field summary "headGasLimit")))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-explicit-dev-gaslimit-overrides-geth-miner-config-file
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-miner-config-override"))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file
            config-path
            "[Eth.Miner]
GasCeil = 34000000
")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--dev"
                         "--dev.gaslimit"
                         "35000000"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (eq t (fixture-object-field summary "devMode")))
             (is (= 35000000
                    (fixture-object-field summary "headGasLimit")))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-empty-geth-http-host-disables-public-rpc
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-config-http-disabled"))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file
            config-path
            "[Node]
HTTPHost = \"\"
HTTPPort = 1945
AuthAddr = \"192.0.2.42\"
AuthPort = 1951
")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (eq nil (fixture-object-field summary "publicRpcEnabled")))
             (is (eq nil (fixture-object-field summary "rpcEndpoint")))
             (is (string= "192.0.2.42:1951"
                          (fixture-object-field summary "engineEndpoint")))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-explicit-http-reenables-empty-geth-http-host
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-geth-config-http-reenabled"))
         (config-path (merge-pathnames "geth.toml" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (ensure-directories-exist root)
           (devnet-cli-write-temp-file
            config-path
            "[Node]
HTTPHost = \"\"
HTTPPort = 1945
")
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--config" (namestring config-path)
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--http"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (eq t (fixture-object-field summary "publicRpcEnabled")))
             (is (string= "127.0.0.1:1945"
                          (fixture-object-field summary "rpcEndpoint")))))
      (when (probe-file config-path)
        (delete-file config-path)))))

(deftest devnet-cli-main-geth-p2p-port-does-not-override-engine-port
  (labels ((run-summary (args)
             (let ((output (make-string-output-stream))
                   (errors (make-string-output-stream)))
               (is (= 0
                      (ethereum-lisp.cli:main
                       (append (list "devnet"
                                     "--genesis"
                                     +devnet-cli-genesis-fixture+)
                               args
                               (list "--json" "--no-serve"))
                       :output-stream output
                       :error-stream errors)))
               (is (string= "" (get-output-stream-string errors)))
               (parse-json (get-output-stream-string output)))))
    (let ((p2p-after-authrpc
            (run-summary
             (list "--authrpc.port=9651"
                   "--port=30303"
                   "--http.port=9645")))
          (p2p-before-authrpc
            (run-summary
             (list "--port=30303"
                   "--authrpc.port=9652"
                   "--http.port=9646")))
          (p2p-without-authrpc
            (run-summary
             (list "--port=30303"
                   "--http.port=9647"))))
      (is (string= "127.0.0.1:9651"
                   (fixture-object-field p2p-after-authrpc
                                         "engineEndpoint")))
      (is (string= "127.0.0.1:9652"
                   (fixture-object-field p2p-before-authrpc
                                         "engineEndpoint")))
      (is (string= "127.0.0.1:8551"
                   (fixture-object-field p2p-without-authrpc
                                         "engineEndpoint")))
      (is (string= "127.0.0.1:9645"
                   (fixture-object-field p2p-after-authrpc
                                         "rpcEndpoint")))
      (is (string= "127.0.0.1:9646"
                   (fixture-object-field p2p-before-authrpc
                                         "rpcEndpoint")))
      (is (string= "127.0.0.1:9647"
                   (fixture-object-field p2p-without-authrpc
                                         "rpcEndpoint"))))))

(deftest devnet-cli-main-accepts-geth-style-txpool-and-database-flags
  (let ((journal-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-geth-txpool" "sexp"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         (format nil "--genesis=~A"
                                 +devnet-cli-genesis-fixture+)
                         "--db.engine=pebble"
                         "--state.scheme=hash"
                         "--datadir.ancient=/tmp/ethereum-lisp-ancient"
                         "--rpc.allow-unprotected-txs=true"
                         "--txpool.locals=0x0000000000000000000000000000000000000001"
                         "--txpool.nolocals=false"
                         (format nil "--txpool.journal=~A"
                                 (namestring journal-path))
                         "--txpool.rejournal=1h"
                         "--txpool.pricelimit=1"
                         "--txpool.pricebump=10"
                         "--txpool.accountslots=16"
                         "--txpool.globalslots=5120"
                         "--txpool.accountqueue=64"
                         "--txpool.globalqueue=1024"
                         "--txpool.lifetime=3h0m0s"
                         "--txpool.blobpool.datacap=2684354560"
                         "--txpool.blobpool.pricebump=100"
                         "--dev=false"
                         "--nousb=true"
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let ((summary (parse-json (get-output-stream-string output))))
             (is (string= "127.0.0.1:8551"
                          (fixture-object-field summary "engineEndpoint")))
             (is (string= "127.0.0.1:8545"
                          (fixture-object-field summary "rpcEndpoint")))
             (is (eq t (fixture-object-field summary
                                              "allowUnprotectedTransactions")))
             (is (= 1 (fixture-object-field summary "txpoolPriceLimit")))
             (is (= 10 (fixture-object-field summary "txpoolPriceBump")))
             (is (= 16 (fixture-object-field summary "txpoolAccountSlots")))
             (is (= 5120 (fixture-object-field summary "txpoolGlobalSlots")))
             (is (= 64 (fixture-object-field summary "txpoolAccountQueue")))
             (is (= 1024 (fixture-object-field summary "txpoolGlobalQueue")))
             (is (= 10800
                    (fixture-object-field summary "txpoolLifetimeSeconds")))
             (is (= 3600
                    (fixture-object-field summary "txpoolRejournalSeconds")))
             (is (string= (namestring journal-path)
                          (fixture-object-field summary
                                                "txpoolJournalPath")))
             (is (equal '("0x0000000000000000000000000000000000000001")
                        (fixture-object-field summary "txpoolLocals")))
             (is (eq nil (fixture-object-field summary "txpoolNoLocals")))
             (is (eq nil (fixture-object-field summary "authRequired")))))
      (when (probe-file journal-path)
        (delete-file journal-path)))))

(deftest devnet-cli-main-accepts-geth-style-dev-mode-flags
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  (format nil "--genesis=~A" +devnet-cli-genesis-fixture+)
                  "--dev=true"
                  "--dev.period=1"
                  "--dev.gaslimit"
                  "31000000"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (string= "127.0.0.1:8551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "127.0.0.1:8545"
                   (fixture-object-field summary "rpcEndpoint")))
      (is (= 1
             (fixture-object-field summary "devPeriodSeconds")))
      (is (= #x1c9c380
             (fixture-object-field summary "headGasLimit")))))
  (let ((init-options
          (ethereum-lisp.cli::devnet-cli-init-options
           (list "init"
                 "--dev=true"
                 "--dev.period=1"
                 "--dev.gaslimit"
                 "30000000"
                 "--json=false"))))
    (is (eq :sexp (getf init-options :summary-format)))))

(deftest devnet-cli-main-accepts-geth-style-rpc-limit-flags
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  (format nil "--genesis=~A" +devnet-cli-genesis-fixture+)
                  "--rpc.gascap=50000000"
                  "--rpc.evmtimeout=5s"
                  "--rpc.txfeecap=0"
                  "--rpc.batch-request-limit=1000"
                  "--rpc.batch-response-max-size=25000000"
                  "--http.maxclients=128"
                  "--http.readtimeout=30s"
                  "--http.writetimeout"
                  "30s"
                  "--http.idletimeout=2m"
                  "--override.terminaltotaldifficulty=0"
                  "--override.terminaltotaldifficultypassed=true"
                  "--override.terminalblockhash=0x0000000000000000000000000000000000000000000000000000000000000000"
                  "--override.terminalblocknumber=0"
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string errors)))
    (let ((summary (parse-json (get-output-stream-string output))))
      (is (string= "127.0.0.1:8551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "127.0.0.1:8545"
                   (fixture-object-field summary "rpcEndpoint"))))))

(deftest devnet-cli-merge-overrides-configure-transition-handshake
  (let* ((terminal-block-hash-hex
           "0x2222222222222222222222222222222222222222222222222222222222222222")
         (options
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet"
                  "--override.terminaltotaldifficulty=0x3039"
                  "--override.terminaltotaldifficultypassed=false"
                  "--override.terminalblockhash" terminal-block-hash-hex
                  "--override.terminalblocknumber" "66"
                  "--no-serve")))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path +devnet-cli-genesis-fixture+
            :terminal-total-difficulty
            (getf options :terminal-total-difficulty)
            :terminal-total-difficulty-passed
            (getf options :terminal-total-difficulty-passed)
            :terminal-total-difficulty-passed-specified-p
            (getf options :terminal-total-difficulty-passed-specified-p)
            :terminal-block-hash
            (getf options :terminal-block-hash)
            :terminal-block-number
            (getf options :terminal-block-number)))
         (config (ethereum-lisp.cli:devnet-node-config node))
         (transition
           (ethereum-lisp.core::engine-rpc-transition-configuration-object
            config)))
    (is (= 12345 (chain-config-terminal-total-difficulty config)))
    (is (not (chain-config-terminal-total-difficulty-passed config)))
    (is (string= terminal-block-hash-hex
                 (hash32-to-hex
                  (chain-config-terminal-block-hash config))))
    (is (= 66 (chain-config-terminal-block-number config)))
    (is (string= "0x3039"
                 (fixture-object-field transition
                                       "terminalTotalDifficulty")))
    (is (string= terminal-block-hash-hex
                 (fixture-object-field transition "terminalBlockHash")))
    (is (string= "0x42"
                 (fixture-object-field transition "terminalBlockNumber")))))

(deftest devnet-cli-main-engine-host-does-not-rewrite-public-default
  (let ((engine-output (make-string-output-stream))
        (engine-errors (make-string-output-stream))
        (host-output (make-string-output-stream))
        (host-errors (make-string-output-stream)))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--engine-host" "192.0.2.10"
                  "--engine-port" "9551"
                  "--json"
                  "--no-serve")
            :output-stream engine-output
            :error-stream engine-errors)))
    (is (string= "" (get-output-stream-string engine-errors)))
    (let ((summary (parse-json (get-output-stream-string engine-output))))
      (is (string= "192.0.2.10:9551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "127.0.0.1:8545"
                   (fixture-object-field summary "rpcEndpoint"))))
    (is (= 0
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--genesis" +devnet-cli-genesis-fixture+
                  "--host" "192.0.2.20"
                  "--port" "9552"
                  "--json"
                  "--no-serve")
            :output-stream host-output
            :error-stream host-errors)))
    (is (string= "" (get-output-stream-string host-errors)))
    (let ((summary (parse-json (get-output-stream-string host-output))))
      (is (string= "192.0.2.20:8551"
                   (fixture-object-field summary "engineEndpoint")))
      (is (string= "192.0.2.20:8545"
                   (fixture-object-field summary "rpcEndpoint"))))))

(deftest devnet-cli-main-log-file-records-ready-event
  (let ((ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (log-path (devnet-cli-temp-path "ethereum-lisp-devnet" "log"))
        (pid-path (devnet-cli-temp-path "ethereum-lisp-devnet" "pid"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (let ((log-path-string (namestring log-path)))
             (is (= 0
                    (ethereum-lisp.cli:main
                     (list "devnet"
                           "--genesis" +devnet-cli-genesis-fixture+
                           "--engine-port" "0"
                           "--public-port" "8546"
                           "--ready-file" (namestring ready-path)
                           "--log-file" log-path-string
                           "--pid-file" (namestring pid-path)
                           "--json"
                           "--no-serve")
                     :output-stream output
                     :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path)))
                  (log-records (devnet-cli-file-forms log-path))
                  (log-names
                    (mapcar (lambda (record) (getf record :name))
                            log-records)))
             (dolist (summary (list stdout-summary ready-summary))
               (is (string= log-path-string
                            (fixture-object-field summary "logPath"))))
             (is (= (devnet-cli-current-process-id)
                    (devnet-cli-pid-file-process-id pid-path)))
             (is (member "devnet.ready" log-names :test #'string=))
             (is (member "devnet.shutdown" log-names :test #'string=))
             (dolist (log-record log-records)
               (let ((fields (getf log-record :fields)))
                 (is (eq :log (getf log-record :kind)))
                 (is (eq :info (getf log-record :value)))
                 (is (string= "127.0.0.1:0"
                              (cdr (assoc "engineEndpoint" fields
                                          :test #'string=))))
                 (is (string= "127.0.0.1:8546"
                              (cdr (assoc "rpcEndpoint" fields
                                          :test #'string=))))
                 (is (string= (if (string= "devnet.ready"
                                            (getf log-record :name))
                                   "ready"
                                   "shutdown")
                              (cdr (assoc "lifecyclePhase" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "engineConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "publicConnections" fields
                                          :test #'string=))))
                 (is (string= "0"
                              (cdr (assoc "totalConnections" fields
                                          :test #'string=))))
                 (is (string= (devnet-cli-current-process-id-string)
                              (cdr (assoc "processId" fields
                                          :test #'string=))))
                 (is (string= "0x539"
                              (cdr (assoc "chainId" fields :test #'string=))))
                 (is (string= "0x0"
                              (cdr (assoc "headNumber" fields
                                          :test #'string=))))
                 (is (stringp
                      (cdr (assoc "headHash" fields :test #'string=))))
                 (is (string= "true"
                              (cdr (assoc "stateAvailable" fields
                                          :test #'string=))))
                 (is (string= log-path-string
                              (cdr (assoc "logPath" fields
                                          :test #'string=))))
                 (is (string= (namestring pid-path)
                              (cdr (assoc "pidFilePath" fields
                                          :test #'string=)))))))))
      (when (probe-file ready-path)
        (delete-file ready-path))
      (when (probe-file log-path)
        (delete-file log-path))
      (when (probe-file pid-path)
        (delete-file pid-path)))))

(deftest devnet-cli-main-log-file-records-error-event
  (let* ((root (devnet-cli-temp-directory
                "ethereum-lisp-devnet-error-artifacts"))
         (log-path (merge-pathnames "errors/nested/devnet-error.log" root))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (unwind-protect
         (let ((log-path-string (namestring log-path)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--log-file" log-path-string
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string output)))
           (is (search "--genesis is required"
                       (get-output-stream-string errors)))
           (let* ((log-records (devnet-cli-file-forms log-path))
                  (record (first log-records))
                  (fields (getf record :fields)))
             (is (= 1 (length log-records)))
             (is (eq :log (getf record :kind)))
             (is (eq :error (getf record :value)))
             (is (string= "devnet.error" (getf record :name)))
             (is (string= "error"
                          (cdr (assoc "lifecyclePhase"
                                      fields
                                      :test #'string=))))
             (is (string= "1"
                          (cdr (assoc "exitCode" fields :test #'string=))))
             (is (string= (devnet-cli-current-process-id-string)
                          (cdr (assoc "processId" fields :test #'string=))))
             (is (search "--genesis is required"
                         (cdr (assoc "errorMessage"
                                     fields
                                     :test #'string=))))
             (is (string= log-path-string
                          (cdr (assoc "logPath" fields :test #'string=))))))
      (when (probe-file log-path)
        (delete-file log-path)))))

(deftest devnet-cli-main-invalid-error-log-path-still-reports-error
  (let* ((log-directory
           (devnet-cli-temp-directory
            "ethereum-lisp-devnet-error-log-directory"))
         (output (make-string-output-stream))
         (errors (make-string-output-stream)))
    (is (= 1
           (ethereum-lisp.cli:main
            (list "devnet"
                  "--log-file" (namestring log-directory)
                  "--json"
                  "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string output)))
    (let ((stderr (get-output-stream-string errors)))
      (is (search "--genesis is required" stderr))
      (is (search "Usage: ethereum-lisp devnet" stderr)))))

(deftest devnet-cli-main-log-file-records-option-parse-error-event
  (let ((log-path (devnet-cli-temp-path "ethereum-lisp-devnet-parse-error"
                                        "log"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (let ((log-path-string (namestring log-path)))
           (is (= 1
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--http"
                         "false"
                         "--ws.api"
                         "eth,net"
                         "--txpool.blobpool.pricebump"
                         "100"
                         (format nil "--log-file=~A" log-path-string)
                         (format nil "--genesis=~A"
                                 +devnet-cli-genesis-fixture+)
                         "--public-port=not-a-port"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string output)))
           (is (search "--public-port requires an integer value"
                       (get-output-stream-string errors)))
           (let* ((log-records (devnet-cli-file-forms log-path))
                  (record (first log-records))
                  (fields (getf record :fields)))
             (is (= 1 (length log-records)))
             (is (eq :log (getf record :kind)))
             (is (eq :error (getf record :value)))
             (is (string= "devnet.error" (getf record :name)))
             (is (string= "error"
                          (cdr (assoc "lifecyclePhase"
                                      fields
                                      :test #'string=))))
             (is (string= "1"
                          (cdr (assoc "exitCode" fields :test #'string=))))
             (is (string= (devnet-cli-current-process-id-string)
                          (cdr (assoc "processId" fields :test #'string=))))
             (is (search "--public-port requires an integer value"
                         (cdr (assoc "errorMessage"
                                     fields
                                     :test #'string=))))
             (is (string= log-path-string
                          (cdr (assoc "logPath" fields :test #'string=))))))
      (when (probe-file log-path)
        (delete-file log-path)))))

