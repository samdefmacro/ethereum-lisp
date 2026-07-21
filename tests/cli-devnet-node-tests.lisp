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

(deftest devnet-node-store-rebind-preserves-live-database-tracking
  (let ((database-path
          (devnet-cli-temp-path "ethereum-lisp-rebind-database" "sexp")))
    (unwind-protect
         (let* ((node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-path +devnet-cli-genesis-fixture+
                   :port 0
                   :database-path (namestring database-path)))
                (replacement-store (make-engine-payload-memory-store))
                (config (ethereum-lisp.cli:devnet-node-config node)))
           (is (not
                (ethereum-lisp.txpool:engine-payload-store-txpool-database-change-tracking-enabled-p
                 replacement-store)))
           (devnet-cli-set-node-store-config
            node replacement-store config)
           (is (eq replacement-store
                   (ethereum-lisp.cli:devnet-node-store node)))
           (is (ethereum-lisp.txpool:engine-payload-store-txpool-database-change-tracking-enabled-p
                replacement-store)))
      (when (probe-file database-path)
        (delete-file database-path)))))

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
              (ethereum-lisp.rpc-http:engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter)))
          (chain-id-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"eth_chainId\",\"params\":[]}"
              engine-store
              engine-config
              :network-id
              (ethereum-lisp.rpc-http:engine-rpc-http-service-network-id
               public-service)
              :coinbase
              (ethereum-lisp.rpc-http:engine-rpc-http-service-coinbase
               public-service)
              :allowed-method-p public-filter)))
          (public-coinbase-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"eth_coinbase\",\"params\":[]}"
              engine-store
              engine-config
              :network-id
              (ethereum-lisp.rpc-http:engine-rpc-http-service-network-id
               public-service)
              :coinbase
              (ethereum-lisp.rpc-http:engine-rpc-http-service-coinbase
               public-service)
              :allowed-method-p public-filter)))
          (network-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"net_version\",\"params\":[]}"
              engine-store
              engine-config
              :network-id
              (ethereum-lisp.rpc-http:engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter))))
      (is (string= (address-to-hex coinbase)
                   (getf (ethereum-lisp.cli:devnet-node-summary node)
                         :coinbase)))
      (is (bytes= (address-bytes coinbase)
                  (address-bytes
                   (ethereum-lisp.rpc-http:engine-rpc-http-service-coinbase
                    engine-service))))
      (is (bytes= (address-bytes coinbase)
                  (address-bytes
                   (ethereum-lisp.rpc-http:engine-rpc-http-service-coinbase
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
              (ethereum-lisp.rpc-http:engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter)))
          (web3-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"web3_clientVersion\",\"params\":[]}"
              store
              config
              :network-id
              (ethereum-lisp.rpc-http:engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter)))
          (rpc-modules-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"rpc_modules\",\"params\":[]}"
              store
              config
              :network-id
              (ethereum-lisp.rpc-http:engine-rpc-http-service-network-id
               public-service)
              :allowed-method-p public-filter)))
          (txpool-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"txpool_status\",\"params\":[]}"
              store
              config
              :network-id
              (ethereum-lisp.rpc-http:engine-rpc-http-service-network-id
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
  (:layer :integration :module :devnet :requires-local-sockets t)
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
  (:layer :integration :module :devnet :requires-local-sockets t)
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
  (:layer :integration :module :devnet :requires-local-sockets t)
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
                  (token (engine-rpc-make-jwt-token secret (unix-time)))
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
  (:layer :integration :module :devnet :requires-local-sockets t)
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
                  (token (engine-rpc-make-jwt-token secret (unix-time)))
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
                             (cons "params" #())))
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
  (:layer :integration :module :devnet :requires-local-sockets t)
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
  (:layer :integration :module :devnet :requires-local-sockets t)
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
  (:layer :integration :module :devnet :requires-local-sockets t)
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
  (:layer :integration :module :devnet :requires-local-sockets t)
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
  (:layer :integration :module :devnet :requires-local-sockets t)
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
