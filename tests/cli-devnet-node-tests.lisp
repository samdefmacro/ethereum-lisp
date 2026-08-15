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
    ;; The Engine port serves the nine `eth` methods the spec obliges it to, so
    ;; a consensus client can read state and logs over the same connection.
    (is (funcall (engine-rpc-http-service-allowed-method-p
                  (ethereum-lisp.cli:devnet-node-service node))
                 "eth_chainId"))
    ;; And nothing beyond them: the authenticated surface is the size of its
    ;; contract, not the size of what happens to be implemented.
    (is (not (funcall (engine-rpc-http-service-allowed-method-p
                       (ethereum-lisp.cli:devnet-node-service node))
                      "eth_getBalance")))
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
            ;; An `eth` method the Engine API spec does NOT oblige the endpoint
            ;; to serve. The nine it does are allowed there -- a consensus
            ;; client reads state and logs over the same connection -- but the
            ;; split still exists, and this is what proves it.
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"eth_coinbase\",\"params\":[]}"
              engine-store
              engine-config
              :allowed-method-p engine-filter)))
          (engine-chain-id-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"eth_chainId\",\"params\":[]}"
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
      ;; And the same method answers on the Engine port, which is the half a
      ;; live Lighthouse needed and did not get.
      (is (string= "0x539"
                   (fixture-object-field engine-chain-id-response "result")))
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

(deftest devnet-cli-peer-option-accumulates-and-validates-enodes
  (let* ((enode-a (concatenate 'string "enode://"
                               (make-string 128 :initial-element #\a)
                               "@127.0.0.1:30303"))
         (enode-b (concatenate 'string "enode://"
                               (make-string 128 :initial-element #\b)
                               "@10.0.0.2:30304"))
         (options (ethereum-lisp.cli::devnet-cli-options
                   (list "devnet" "--peer" enode-a "--peer" enode-b "--no-serve"))))
    ;; Repeated --peer flags accumulate in command-line order.
    (is (equal (list enode-a enode-b) (getf options :peers)))
    ;; No peers means an empty list.
    (is (null (getf (ethereum-lisp.cli::devnet-cli-options (list "devnet" "--no-serve"))
                    :peers)))
    ;; A malformed enode is rejected at parse time.
    (signals error
      (ethereum-lisp.cli::devnet-cli-options
       (list "devnet" "--peer" "not-an-enode" "--no-serve")))))

(defun devnet-peer-sync-test-drop-cached-rocksdb-handle (database-path)
  "Close and forget DATABASE-PATH's test-scoped RocksDB handle.

The live CLI intentionally holds one RocksDB handle for the node lifetime.  A
durability restart test has to end that lifetime explicitly so its second node
really reopens the directory instead of observing the first handle's memory."
  (let ((cache ethereum-lisp.cli::*devnet-cli-kv-database-cache*))
    (when cache
      (let* ((key
               (ethereum-lisp.cli::devnet-cli-kv-database-cache-key
                database-path))
             (database (gethash key cache)))
        (remhash key cache)
        (when database
          (ethereum-lisp.database:close-rocksdb-key-value-database
           database)))))
  nil)

(defun devnet-peer-sync-assert-durable-candidates (store blocks)
  "Assert BLOCKS are executable candidates, never canonical publications."
  (is (= 0 (chain-store-head-number store)))
  (dolist (block blocks)
    (let* ((hash (block-hash block))
           (number (block-header-number (block-header block))))
      (is (null (chain-store-canonical-hash store number)))
      (is (not (null (chain-store-known-block store hash))))
      (is (chain-store-state-available-p store hash)))))

(defun devnet-peer-sync-test-alternate-empty-child (parent config marker)
  (ethereum-lisp.engine-payloads:engine-build-empty-payload
   parent
   (make-payload-attributes-v1
    :timestamp (+ 12 (block-header-timestamp (block-header parent)))
    :prev-randao
    (make-hash32 (make-byte-vector 32 :initial-element marker))
    :suggested-fee-recipient (zero-address))
   config))

(defun devnet-peer-sync-durable-resume-case
    (database-path db-engine &key before-restart)
  "Exercise peer candidate and cursor durability for one database backend."
  (let* ((first-node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :database-path database-path
            :db-engine db-engine
            :port 0 :public-port 0))
         (config (ethereum-lisp.cli::devnet-node-config first-node))
         (genesis-block
           (ethereum-lisp.cli::devnet-node-genesis-block first-node))
         (genesis-hash (block-hash genesis-block))
         (blocks (eth-sync-produce-empty-blocks genesis-block config 3))
         ;; A real, deterministic secp256k1 public key: the durable cursor is
         ;; keyed by the same 64-byte identity the downloader derives from an
         ;; enode URL.
         (peer-id
           (secp256k1-private-key-public-key
            #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)))
    (dolist (block blocks)
      (multiple-value-bind (status candidate receipts)
          (ethereum-lisp.cli::devnet-peer-sync-import-block
           first-node block :peer-id peer-id :require-valid-p t)
        (declare (ignore receipts))
        (is (string= +payload-status-valid+
                     (payload-status-status status)))
        (is (hash32= (block-hash block) (block-hash candidate)))))
    (devnet-peer-sync-assert-durable-candidates
     (ethereum-lisp.cli::devnet-node-store first-node) blocks)
    (when before-restart
      (funcall before-restart))
    (let* ((second-node
             (ethereum-lisp.cli:make-devnet-node
              :genesis-json *eth-sync-paris-genesis-json*
              :database-path database-path
              :db-engine db-engine
              :port 0 :public-port 0))
           (restored-store
             (ethereum-lisp.cli::devnet-node-store second-node))
           (tip (car (last blocks)))
           (tip-hash (block-hash tip))
           (funded
             (address-from-hex
              "0x0000000000000000000000000000000000001001")))
      (devnet-peer-sync-assert-durable-candidates restored-store blocks)
      ;; State availability is not merely a persisted marker: the restarted
      ;; provider can answer a state lookup using the candidate hash.
      (is (= #xde0b6b3a7640000
             (chain-store-account-balance restored-store tip-hash funded)))
      (multiple-value-bind (start-number expected-parent-hash)
          (ethereum-lisp.cli::devnet-node-peer-sync-resume-point
           second-node peer-id 0 genesis-hash)
        (is (= (1+ (block-header-number (block-header tip))) start-number))
        (is (hash32= tip-hash expected-parent-hash))))))

(deftest devnet-peer-sync-durable-resume-round-trips-on-file-database
  (let* ((datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-peer-sync-file-resume"))
         (database-path
           (ethereum-lisp.cli::devnet-cli-datadir-database-path
            datadir :file)))
    (unwind-protect
         (devnet-peer-sync-durable-resume-case database-path :file)
      (uiop:delete-directory-tree datadir
                                  :validate t
                                  :if-does-not-exist :ignore))))

(deftest devnet-peer-sync-durable-resume-round-trips-on-rocksdb
  (let* ((datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-peer-sync-rocksdb-resume"))
         (database-path
           (ethereum-lisp.cli::devnet-cli-datadir-database-path
            datadir :rocksdb)))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (unwind-protect
                 (devnet-peer-sync-durable-resume-case
                  database-path
                  :rocksdb
                  :before-restart
                  (lambda ()
                    (devnet-peer-sync-test-drop-cached-rocksdb-handle
                     database-path)))
              (devnet-peer-sync-test-drop-cached-rocksdb-handle
               database-path))))
      (uiop:delete-directory-tree datadir
                                  :validate t
                                  :if-does-not-exist :ignore))))

(deftest devnet-peer-sync-resets-an-abandoned-branch-cursor
  (:layer :integration :module :p2p)
  (let* ((datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-peer-sync-cursor-rebase"))
         (database-path
           (ethereum-lisp.cli::devnet-cli-datadir-database-path
            datadir :file)))
    (unwind-protect
         (let* ((node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-json *eth-sync-paris-genesis-json*
                   :database-path database-path
                   :db-engine :file
                   :port 0 :public-port 0))
                (store (ethereum-lisp.cli::devnet-node-store node))
                (config (ethereum-lisp.cli::devnet-node-config node))
                (genesis
                  (ethereum-lisp.cli::devnet-node-genesis-block node))
                (genesis-hash (block-hash genesis))
                (old-branch
                  (eth-sync-produce-empty-blocks genesis config 3))
                (peer-id
                  (secp256k1-private-key-public-key
                   #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee))
                (new-head
                  (devnet-peer-sync-test-alternate-empty-child
                   genesis config 91))
                (new-child
                  (devnet-peer-sync-test-alternate-empty-child
                   new-head config 92)))
           (dolist (block old-branch)
             (ethereum-lisp.cli::devnet-peer-sync-import-block
              node block :peer-id peer-id :require-valid-p t))
           (ethereum-lisp.cli::devnet-peer-sync-import-block
            node new-head :require-valid-p t)
           (ethereum-lisp.cli::call-with-devnet-node-store-guard
            node
            (lambda ()
              (publish-canonical-block
               store new-head config
               :authority :engine-forkchoice
               :forkchoice-state
               (make-forkchoice-state
                :head-block-hash (block-hash new-head)
                :safe-block-hash genesis-hash
                :finalized-block-hash genesis-hash)
               :durability-function
               (ethereum-lisp.cli::devnet-node-canonical-transition-persistence-function
                node))))
           (multiple-value-bind (start-number expected-parent-hash)
               (ethereum-lisp.cli::devnet-node-peer-sync-resume-point
                node peer-id 1 (block-hash new-head))
             (is (= 2 start-number))
             (is (hash32= (block-hash new-head) expected-parent-hash)))
           ;; The obsolete height-3 cursor is gone before a lower new-branch
           ;; cursor is attempted.
           (multiple-value-bind (progress present-p)
               (funcall
                (ethereum-lisp.cli::devnet-node-peer-sync-progress-function
                 node)
                peer-id)
             (is (null progress))
             (is (not present-p)))
           (ethereum-lisp.cli::devnet-peer-sync-import-block
            node new-child :peer-id peer-id :require-valid-p t)
           (multiple-value-bind (progress present-p)
               (funcall
                (ethereum-lisp.cli::devnet-node-peer-sync-progress-function
                 node)
                peer-id)
             (is present-p)
             (when progress
               (is (= 2
                      (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-last-number
                       progress)))
               (is (hash32=
                    (block-hash new-child)
                    (ethereum-lisp.node-store.persistence:node-store-peer-sync-progress-last-hash
                     progress))))))
      (uiop:delete-directory-tree datadir
                                  :validate t
                                  :if-does-not-exist :ignore))))

(deftest devnet-peer-sync-rebases-on-a-remote-branch-change-once
  (:layer :integration :module :p2p)
  (let* ((datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-peer-sync-remote-reorg"))
         (database-path
           (ethereum-lisp.cli::devnet-cli-datadir-database-path
            datadir :file)))
    (unwind-protect
         (let* ((node
                  (ethereum-lisp.cli:make-devnet-node
                   :genesis-json *eth-sync-paris-genesis-json*
                   :database-path database-path :db-engine :file
                   :port 0 :public-port 0))
                (config (ethereum-lisp.cli::devnet-node-config node))
                (genesis
                  (ethereum-lisp.cli::devnet-node-genesis-block node))
                (genesis-hash (block-hash genesis))
                (old-branch
                  (eth-sync-produce-empty-blocks genesis config 2))
                (old-tip (car (last old-branch)))
                (peer-id
                  (secp256k1-private-key-public-key
                   #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee))
                (calls 0))
           (dolist (block old-branch)
             (ethereum-lisp.cli::devnet-peer-sync-import-block
              node block :peer-id peer-id :require-valid-p t))
           (devnet-peer-sync-call-with-function-overrides
            (list
             (cons
              'ethereum-lisp.eth-sync:eth-peer-get-block-headers
              (lambda (peer &key origin-number amount &allow-other-keys)
                (is (eq :peer peer))
                (is (= 1 amount))
                (is (= 2 origin-number))
                (list (block-header old-tip))))
             (cons
              'ethereum-lisp.eth-sync:eth-sync-download-blocks
              (lambda (peer import-block
                       &key start-number expected-parent-hash &allow-other-keys)
                (declare (ignore import-block))
                (is (eq :peer peer))
                (incf calls)
                (ecase calls
                  (1
                   (is (= 3 start-number))
                   (is (hash32= (block-hash old-tip)
                                expected-parent-hash))
                   (error 'ethereum-lisp.eth-sync:eth-sync-anchor-mismatch
                          :number 3
                          :expected-parent-hash expected-parent-hash
                          :actual-parent-hash (zero-hash32)))
                  (2
                   (is (= 1 start-number))
                   (is (hash32= genesis-hash expected-parent-hash))
                   0)))))
            (lambda ()
              (is (= 0
                     (ethereum-lisp.cli::devnet-peer-download-from-resume
                      node :peer peer-id 0 genesis-hash)))))
           (is (= 2 calls))
           (multiple-value-bind (progress present-p)
               (funcall
                (ethereum-lisp.cli::devnet-node-peer-sync-progress-function
                 node)
                peer-id)
             (is (null progress))
             (is (not present-p)))
           ;; If the peer reorged to a shorter/equal-height chain, probing the
           ;; old cursor returns no header.  Recreate the cursor and prove the
           ;; helper rebases before issuing a cursor+1 range that would look
           ;; like an ordinary end-of-chain response.
           (dolist (block old-branch)
             (ethereum-lisp.cli::devnet-peer-sync-import-block
              node block :peer-id peer-id :require-valid-p t))
           (setf calls 0)
           (devnet-peer-sync-call-with-function-overrides
            (list
             (cons
              'ethereum-lisp.eth-sync:eth-peer-get-block-headers
              (lambda (peer &key origin-number amount &allow-other-keys)
                (declare (ignore peer origin-number amount))
                nil))
             (cons
              'ethereum-lisp.eth-sync:eth-sync-download-blocks
              (lambda (peer import-block
                       &key start-number expected-parent-hash &allow-other-keys)
                (declare (ignore peer import-block))
                (incf calls)
                (is (= 1 start-number))
                (is (hash32= genesis-hash expected-parent-hash))
                0)))
            (lambda ()
              (is (= 0
                     (ethereum-lisp.cli::devnet-peer-download-from-resume
                      node :peer peer-id 0 genesis-hash)))))
           (is (= 1 calls))
           (multiple-value-bind (progress present-p)
               (funcall
                (ethereum-lisp.cli::devnet-node-peer-sync-progress-function
                 node)
                peer-id)
             (is (null progress))
             (is (not present-p)))
           ;; With no cursor left, a canonical-anchor mismatch is not retried.
           (setf calls 0)
           (devnet-peer-sync-call-with-function-overrides
            (list
             (cons
              'ethereum-lisp.eth-sync:eth-sync-download-blocks
              (lambda (peer import-block
                       &key start-number expected-parent-hash &allow-other-keys)
                (declare (ignore peer import-block))
                (incf calls)
                (is (= 1 start-number))
                (is (hash32= genesis-hash expected-parent-hash))
                (error 'ethereum-lisp.eth-sync:eth-sync-anchor-mismatch
                       :number 1
                       :expected-parent-hash expected-parent-hash
                       :actual-parent-hash (zero-hash32)))))
            (lambda ()
              (signals ethereum-lisp.eth-sync:eth-sync-anchor-mismatch
                (ethereum-lisp.cli::devnet-peer-download-from-resume
                 node :peer peer-id 0 genesis-hash))))
           (is (= 1 calls)))
      (uiop:delete-directory-tree datadir
                                  :validate t
                                  :if-does-not-exist :ignore))))

;; The resumed downloader passes its EXPECTED-PARENT-HASH to header batch
;; validation.  ETH-SYNC-RESUME-ANCHOR-REJECTS-A-DIFFERENT-FIRST-PARENT covers
;; the complementary failure case: a peer cannot continue from another parent.

(defun devnet-peer-sync-call-with-function-overrides (bindings thunk)
  "Call THUNK with global function BINDINGS, restoring every definition."
  (let ((originals
          (mapcar (lambda (binding)
                    (cons (car binding) (fdefinition (car binding))))
                  bindings)))
    (unwind-protect
         (progn
           (dolist (binding bindings)
             (setf (fdefinition (car binding)) (cdr binding)))
           (funcall thunk))
      (dolist (binding originals)
        (setf (fdefinition (car binding)) (cdr binding))))))

(deftest devnet-chain-update-does-not-send-legacy-block-gossip-to-eth69-peers
  (:layer :unit :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (modern
           (ethereum-lisp.eth-sync::%make-eth-peer
            :eth-version ethereum-lisp.eth-wire:+eth-protocol-version-71+))
         (legacy
           (ethereum-lisp.eth-sync::%make-eth-peer
            :eth-version ethereum-lisp.eth-wire:+eth-protocol-version+))
         (range-calls '())
         (message-calls '()))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.eth-sync:eth-peer-send-block-range-update
            (lambda (peer earliest latest latest-hash)
              (push (list peer earliest latest latest-hash) range-calls)))
      (cons 'ethereum-lisp.eth-sync:eth-peer-send
            (lambda (peer message-id payload)
              (push (list peer message-id payload) message-calls))))
     (lambda ()
       (let ((send-modern
               (funcall
                (ethereum-lisp.cli::devnet-peer-pending-chain-update
                 node modern))))
         (is (functionp send-modern))
         (funcall send-modern))
       ;; Pinned geth eth/69--72 deliberately has no NewBlockHashes handler.
       (is (= 1 (length range-calls)))
       (is (null message-calls))
       (let ((send-legacy
               (funcall
                (ethereum-lisp.cli::devnet-peer-pending-chain-update
                 node legacy))))
         (is (functionp send-legacy))
         (funcall send-legacy))
       (is (= 1 (length range-calls)))
       (is (= 1 (length message-calls)))
       (is (= ethereum-lisp.eth-wire:+eth-message-new-block-hashes+
              (second (first message-calls))))))))

(deftest devnet-snap-pivot-logs-each-durable-state-page
  (:layer :integration :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (config (ethereum-lisp.cli::devnet-node-config node))
         (genesis (ethereum-lisp.cli::devnet-node-genesis-block node))
         (store (ethereum-lisp.cli::devnet-node-store node))
         (persistence
           (ethereum-lisp.cli::devnet-node-persistence-state node))
         (pivot-header (block-header genesis))
         (pivot-hash (block-header-hash pivot-header))
         (target-hash (make-hash32 (make-byte-vector 32 :initial-element 9)))
         (database (make-memory-key-value-database))
         (state (chain-store-state-db store pivot-hash))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            database state))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range
            (ethereum-lisp.snap:snap-state-backend-account-range backend)
            :storage-ranges
            (ethereum-lisp.snap:snap-state-backend-storage-ranges backend)
            :bytecodes
            (ethereum-lisp.snap:snap-state-backend-bytecodes backend)
            :trie-nodes
            (ethereum-lisp.snap:snap-state-backend-trie-nodes backend)))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry :id-hex "peer-1"))
         (logs '()))
    (declare (ignore config persistence))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons
       'ethereum-lisp.cli::devnet-node-live-sync-entries
       (lambda (seen-node &key snap-only-p)
         (is (eq node seen-node))
         (is snap-only-p)
         (list entry)))
      (cons
       'ethereum-lisp.cli::devnet-peer-queued-snap-source
       (lambda (seen-entry)
         (is (eq entry seen-entry))
         source))
      (cons
       'ethereum-lisp.cli::devnet-peer-manager-log
       (lambda (seen-node name &rest fields)
         (is (eq node seen-node))
         (push (cons name fields) logs))))
     (lambda ()
       (is
        (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
         (ethereum-lisp.cli::devnet-node-snap-import-with-failover
          node database pivot-header target-hash)))))
    (setf logs (nreverse logs))
    (flet ((field (record name)
             (loop for (key value) on (cdr record) by #'cddr
                   when (string= key name) return value)))
      (let ((page-logs
              (remove-if-not
               (lambda (record)
                 (string= "peer.snap.progress" (first record)))
               logs))
            (heal-logs
              (remove-if-not
               (lambda (record)
                 (string= "peer.snap.heal_progress" (first record)))
               logs)))
        (is (plusp (length page-logs)))
        (is (=
             ethereum-lisp.snap-sync::+snap-sync-account-task-count+
             (length
              (remove-duplicates
               (mapcar (lambda (record) (field record "task")) page-logs)))))
        (dolist (record page-logs)
          (is (string= "peer-1" (field record "peer")))
          (is (= (block-header-number pivot-header)
                 (field record "pivot")))
          ;; Page durability is not state completeness. Byte-capped storage may
          ;; still be mandatory work for the final content-addressed traversal.
          (is (null (field record "completed"))))
        ;; The shared source/target database makes this a reuse-only healing
        ;; pass. Its terminal snapshot still reaches the operator log.
        (is (= 1 (length heal-logs)))
        (let ((record (first heal-logs)))
          (is (= (block-header-number pivot-header) (field record "pivot")))
          (is (field record "completed"))
          (is (integerp (field record "processedNodes")))
          (is (integerp (field record "reusedNodes")))
          (is (= 0 (field record "requests")))
          (is (= 0 (field record "fetchedNodes")))
          (is (= 0 (field record "nodeBytes"))))))))

(deftest devnet-snap-heal-progress-throttles-intermediate-events
  (:layer :unit :module :p2p)
  (is (ethereum-lisp.cli::devnet-snap-heal-progress-log-due-p nil 100 nil))
  (is (not (ethereum-lisp.cli::devnet-snap-heal-progress-log-due-p
            100 129 nil)))
  (is (ethereum-lisp.cli::devnet-snap-heal-progress-log-due-p 100 130 nil))
  (is (ethereum-lisp.cli::devnet-snap-heal-progress-log-due-p 100 101 t))
  ;; A backwards-adjusted wall clock must not suppress logs indefinitely.
  (is (ethereum-lisp.cli::devnet-snap-heal-progress-log-due-p 100 99 nil)))

(deftest devnet-snap-target-downloads-only-the-bounded-pivot-tail
  (:layer :integration :module :p2p)
  (let* ((datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-snap-bounded-pivot"))
         (database-path
           (ethereum-lisp.cli::devnet-cli-datadir-database-path
            datadir :rocksdb)))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (unwind-protect
                 (let* ((node
                          (ethereum-lisp.cli:make-devnet-node
                           :genesis-json *eth-sync-paris-genesis-json*
                           :database-path database-path :db-engine :rocksdb
                           :port 0 :public-port 0))
                        (store (ethereum-lisp.cli::devnet-node-store node))
                        (config (ethereum-lisp.cli::devnet-node-config node))
                        (genesis
                          (ethereum-lisp.cli::devnet-node-genesis-block node))
                        (genesis-header (block-header genesis))
                        (fake-parent
                          (make-block
                           :header
                           (make-block-header
                            :parent-hash (block-hash genesis)
                            :beneficiary (zero-address)
                            :state-root
                            (block-header-state-root genesis-header)
                            :mix-hash (zero-hash32)
                            :number 99
                            :gas-limit 30000000
                            :timestamp
                            (+ (block-header-timestamp genesis-header) 1188)
                            :base-fee-per-gas 1000000000)))
                        (blocks
                          (eth-sync-produce-empty-blocks fake-parent config 65))
                        (pivot (first blocks))
                        (target (car (last blocks)))
                        (pivot-hash (block-hash pivot))
                        (target-hash (block-hash target))
                        (stale-newer-target
                          (make-block
                           :header
                           (make-block-header
                            :parent-hash target-hash
                            :beneficiary (zero-address)
                            :state-root
                            (block-header-state-root (block-header target))
                            :mix-hash (zero-hash32)
                            :number
                            (+ (block-header-number (block-header target))
                               121)
                            :gas-limit 30000000
                            :timestamp
                            (+ (block-header-timestamp (block-header target))
                               (* 12 121))
                            :base-fee-per-gas 1000000000)))
                        (stale-newer-target-hash
                          (block-hash stale-newer-target))
                        (newer-target-hash
                          (make-hash32
                           (make-byte-vector 32 :initial-element 42)))
                        (database
                          (ethereum-lisp.node-store.persistence:database-engine-payload-store-database
                           store))
                        (persistence
                          (ethereum-lisp.cli::devnet-node-persistence-state node))
                        (tail-imports 0)
                        (durable-state-progress nil)
                        (download-observation nil))
                   (devnet-peer-sync-call-with-function-overrides
                    (list
                     (cons
                      'ethereum-lisp.cli::devnet-node-resolve-snap-target
                      (lambda (callback-node callback-target)
                        (declare (ignore callback-node))
                        (is (hash32= target-hash callback-target))
                        (values :target-source
                                (block-header target) (block-header pivot)
                                (mapcar #'block-header blocks))))
                     (cons
                      'ethereum-lisp.cli::devnet-node-select-snap-pivot
                      (lambda (callback-node preferred-entry tail-headers)
                        (is (eq node callback-node))
                        (is (eq :target-source preferred-entry))
                        (is (= 65 (length tail-headers)))
                        (values preferred-entry (block-header pivot)
                                tail-headers)))
                     (cons
                      'ethereum-lisp.cli::devnet-node-sync-peer-sources
                      (lambda (callback-node)
                        (declare (ignore callback-node))
                        (list :bounded-source)))
                     (cons
                      'ethereum-lisp.eth-sync:eth-sync-download-blocks-multi
                      (lambda (sources import-block
                               &key start-number target-number
                                    expected-parent-hash expected-target-hash
                                    import-batch &allow-other-keys)
                        (declare (ignore import-block))
                        (setf download-observation
                              (list sources start-number target-number
                                    (hash32= expected-parent-hash
                                             (block-hash fake-parent))
                                    (hash32= expected-target-hash target-hash)))
                        (funcall import-batch blocks)
                        (length blocks)))
                     (cons
                      'ethereum-lisp.cli::devnet-node-snap-import-with-failover
                      (lambda (callback-node callback-database pivot-header
                               callback-target &key preferred-entry)
                        (declare (ignore callback-node))
                        (is (eq :target-source preferred-entry))
                        (is (eq database callback-database))
                        (is (hash32= pivot-hash
                                     (block-header-hash pivot-header)))
                        (is (hash32= target-hash callback-target))
                        ;; The real snap importer writes STATE-HISTORY only in
                        ;; its completed batch after reconstructing this root.
                        (kv-put-chain-record
                         callback-database :state-history
                         (hash32-bytes pivot-hash)
                         (hash32-bytes
                          (block-header-state-root pivot-header)))
                        (setf durable-state-progress
                              (ethereum-lisp.snap-sync::snap-sync-make-progress
                               :pivot-hash pivot-hash :pivot-number 100
                               :state-root
                               (block-header-state-root pivot-header)
                               :partial-root
                               (block-header-state-root pivot-header)
                               :target-hash target-hash
                               :chain-id (chain-config-chain-id config)
                               :genesis-hash (block-hash genesis)
                               :authority-id
                               (ethereum-lisp.cli::devnet-persistence-state-authority-id
                                persistence)
                               :completed-p t))
                        ;; The test double must preserve the real importer's
                        ;; durable state-progress side effect.  That record,
                        ;; not the cheaper skeleton alone, is what protects a
                        ;; long account-range import from advancing FCUs.
                        (let ((batch (make-kv-write-batch)))
                          (ethereum-lisp.snap-sync::snap-sync-populate-progress-batch
                           batch durable-state-progress)
                          (kv-apply-batch callback-database batch))
                        durable-state-progress))
                     (cons
                      'ethereum-lisp.cli::devnet-peer-sync-import-block
                      (lambda (callback-node block &rest arguments)
                        (declare (ignore callback-node arguments))
                        (incf tail-imports)
                        (values
                         (make-payload-status
                          :status +payload-status-valid+)
                         block nil))))
                    (lambda ()
                      (is (= 64
                             (ethereum-lisp.cli::devnet-node-snap-sync-target
                              node target-hash)))))
                   ;; The old implementation started at canonical genesis+1.
                   ;; The bounded implementation starts at the 64-block pivot.
                   (is (equal (list (list :bounded-source) 100 164 t t)
                              download-observation))
                   (is (= 64 tail-imports))
                   (is (= 100 (chain-store-head-number store)))
                   (is (hash32= pivot-hash
                                (chain-store-canonical-hash store 100)))
                   (is (null (chain-store-canonical-hash store 164)))
                   ;; A new FCU arrives every slot while a public Snap import
                   ;; can run for hours.  Its durable session remains pinned
                   ;; until the old target is executable instead of deleting
                   ;; the account cursor on every target update.
                   (is (hash32=
                        target-hash
                        (ethereum-lisp.cli::devnet-node-active-snap-target
                         node newer-target-hash)))
                   ;; Match geth's stale-pivot rule: committed progress is
                   ;; protected across ordinary slots, but a known CL target
                   ;; more than 2*64-8 blocks ahead may move the uninstalled
                   ;; pivot instead of waiting forever for a pruned root.
                   (ethereum-lisp.cli::call-with-devnet-node-store-guard
                    node
                    (lambda ()
                      (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
                       store stale-newer-target)))
                   (is (hash32=
                        stale-newer-target-hash
                        (ethereum-lisp.cli::devnet-node-active-snap-target
                         node stale-newer-target-hash)))
                   ;; A skeleton with no committed account cursor is cheap to
                   ;; abandon and may name a pivot that peers have pruned.
                   (is (ethereum-lisp.snap-sync:snap-sync-delete-progress
                        database))
                   (is (hash32=
                        newer-target-hash
                        (ethereum-lisp.cli::devnet-node-active-snap-target
                         node newer-target-hash)))
                   ;; Recreate the matching durable state session and prove
                   ;; that target executability, not completion of the pivot
                   ;; state record alone, releases the pin.
                   (let ((batch (make-kv-write-batch)))
                     (ethereum-lisp.snap-sync::snap-sync-populate-progress-batch
                      batch durable-state-progress)
                     (kv-apply-batch database batch))
                   (kv-put-chain-record
                    database :state-history (hash32-bytes target-hash)
                    (hash32-bytes
                     (block-header-state-root (block-header target))))
                   (is (hash32=
                        newer-target-hash
                        (ethereum-lisp.cli::devnet-node-active-snap-target
                         node newer-target-hash))))
              (devnet-peer-sync-test-drop-cached-rocksdb-handle
               database-path))))
      (uiop:delete-directory-tree datadir
                                  :validate t
                                  :if-does-not-exist :ignore))))

(deftest devnet-snap-stale-pivot-rebases-skeleton-and-state-together
  (:layer :integration :module :p2p)
  (let* ((datadir
           (devnet-cli-temp-directory
            "ethereum-lisp-snap-atomic-pivot-rebase"))
         (database-path
           (ethereum-lisp.cli::devnet-cli-datadir-database-path
            datadir :rocksdb)))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (unwind-protect
                 (let* ((node
                          (ethereum-lisp.cli:make-devnet-node
                           :genesis-json *eth-sync-paris-genesis-json*
                           :database-path database-path :db-engine :rocksdb
                           :port 0 :public-port 0))
                        (store (ethereum-lisp.cli::devnet-node-store node))
                        (database
                          (ethereum-lisp.node-store.persistence:database-engine-payload-store-database
                           store))
                        (config (ethereum-lisp.cli::devnet-node-config node))
                        (genesis
                          (ethereum-lisp.cli::devnet-node-genesis-block node))
                        (persistence
                          (ethereum-lisp.cli::devnet-node-persistence-state
                           node))
                        (old-anchor
                          (make-hash32
                           (make-byte-vector 32 :initial-element 31)))
                        (old-root
                          (make-hash32
                           (make-byte-vector 32 :initial-element 32)))
                        (old-pivot
                          (make-block-header
                           :parent-hash old-anchor :number 100
                           :state-root old-root :gas-limit 30000000))
                        (old-target
                          (make-block-header
                           :parent-hash (block-header-hash old-pivot)
                           :number 164 :state-root old-root
                           :gas-limit 30000000))
                        (new-anchor
                          (make-hash32
                           (make-byte-vector 32 :initial-element 33)))
                        (new-root
                          (make-hash32
                           (make-byte-vector 32 :initial-element 34)))
                        (new-pivot
                          (make-block-header
                           :parent-hash new-anchor :number 220
                           :state-root new-root :gas-limit 30000000))
                        (new-target
                          (make-block-header
                           :parent-hash (block-header-hash new-pivot)
                           :number 284 :state-root new-root
                           :gas-limit 30000000))
                        (cursor
                          (make-byte-vector 32 :initial-element 1))
                        (state-progress
                          (ethereum-lisp.snap-sync::snap-sync-make-progress
                           :pivot-hash (block-header-hash old-pivot)
                           :pivot-number 100 :state-root old-root
                           :next-origin cursor :partial-root +empty-trie-hash+
                           :target-hash (block-header-hash old-target)
                           :chain-id (chain-config-chain-id config)
                           :genesis-hash (block-hash genesis)
                           :authority-id
                           (ethereum-lisp.cli::devnet-persistence-state-authority-id
                            persistence)
                           :completed-p nil))
                        (skeleton
                          (ethereum-lisp.node-store.persistence:make-node-store-snap-skeleton-progress
                           :authority-id
                           (ethereum-lisp.cli::devnet-persistence-state-authority-id
                            persistence)
                           :chain-id (chain-config-chain-id config)
                           :genesis-hash (block-hash genesis)
                           :target-number 164
                           :target-hash (block-header-hash old-target)
                           :anchor-number 99 :anchor-hash old-anchor
                           :pivot-number 100
                           :pivot-hash (block-header-hash old-pivot)
                           :last-number 164
                           :last-hash (block-header-hash old-target))))
                   (let ((batch (make-kv-write-batch)))
                     (ethereum-lisp.node-store.persistence::node-store-populate-snap-skeleton-progress-batch
                      database batch skeleton)
                     (ethereum-lisp.snap-sync::snap-sync-populate-progress-batch
                      batch state-progress)
                     (kv-apply-batch database batch))
                   (ethereum-lisp.cli::call-with-devnet-node-store-guard
                    node
                    (lambda ()
                      (ethereum-lisp.cli::devnet-node-rebase-stale-snap-progress
                       node database new-target new-pivot)))
                   (multiple-value-bind (restored present-p)
                       (ethereum-lisp.node-store.persistence:node-store-read-snap-skeleton-progress
                        database)
                     (is present-p)
                     (is (= 219
                            (ethereum-lisp.node-store.persistence:node-store-snap-skeleton-progress-last-number
                             restored)))
                     (is (hash32= new-anchor
                                  (ethereum-lisp.node-store.persistence:node-store-snap-skeleton-progress-last-hash
                                   restored)))
                     (is (hash32= (block-header-hash new-pivot)
                                  (ethereum-lisp.node-store.persistence:node-store-snap-skeleton-progress-pivot-hash
                                   restored))))
                   (multiple-value-bind (restored present-p)
                       (ethereum-lisp.snap-sync:snap-sync-read-progress database)
                     (is present-p)
                     (is (hash32= (block-header-hash new-target)
                                  (ethereum-lisp.snap-sync:snap-sync-progress-target-hash
                                   restored)))
                     (is (hash32= (block-header-hash new-pivot)
                                  (ethereum-lisp.snap-sync:snap-sync-progress-pivot-hash
                                   restored)))
                     (is (bytes= cursor
                                 (ethereum-lisp.snap-sync:snap-sync-progress-next-origin
                                  restored)))
                     (is (not
                          (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                           restored))))
                   ;; Rebase is metadata only; the new root remains private
                   ;; until TrieNodes healing reaches its final atomic batch.
                   (is (not
                        (nth-value
                         1
                         (kv-get-chain-record
                          database :state-history
                          (hash32-bytes (block-header-hash new-pivot)))))))
              (devnet-peer-sync-test-drop-cached-rocksdb-handle
               database-path))))
      (uiop:delete-directory-tree datadir
                                  :validate t
                                  :if-does-not-exist :ignore))))

(deftest devnet-snap-target-unavailable-does-not-poison-peer-score
  (:layer :integration :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (peer-id "temporarily-behind-snap-peer")
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex peer-id :peer :peer :request-queue :queue))
         (table (ethereum-lisp.cli::devnet-node-peer-table node))
         (target (make-hash32 (make-byte-vector 32 :initial-element 7))))
    (flet ((run-failure (condition)
             (devnet-peer-sync-call-with-function-overrides
              (list
               (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
                     (lambda (callback-node &key snap-only-p)
                       (declare (ignore callback-node snap-only-p))
                       (list entry)))
               (cons 'ethereum-lisp.cli::devnet-peer-resolve-snap-target
                     (lambda (callback-entry callback-target)
                       (declare (ignore callback-entry callback-target))
                       (error condition))))
              (lambda ()
                (signals ethereum-lisp.eth-sync:eth-sync-multi-peer-error
                  (ethereum-lisp.cli::devnet-node-resolve-snap-target
                   node target))))))
      ;; A healthy peer may trail a fresh CL target. Repeated coordinator ticks
      ;; must not turn that ordinary availability lag into a permanent ban.
      (run-failure
       (make-condition 'ethereum-lisp.cli::devnet-snap-target-unavailable
                       :format-control "target not imported yet"
                       :format-arguments nil))
      (is (= 0 (ethereum-lisp.cli::devnet-peer-score table peer-id)))
      ;; Queue/session closure is also transient at this layer. The owning
      ;; session applies its own gradual disconnect policy.
      (run-failure
       (make-condition 'simple-error
                       :format-control "peer session closed"
                       :format-arguments nil))
      (is (= 0 (ethereum-lisp.cli::devnet-peer-score table peer-id)))
      ;; Positive control: a contradictory response still carries the existing
      ;; malformed-peer penalty, proving the scoring branch was exercised.
      (run-failure
       (make-condition 'ethereum-lisp.cli::devnet-snap-target-malformed
                       :format-control "wrong target header"
                       :format-arguments nil))
      (is (= -50 (ethereum-lisp.cli::devnet-peer-score table peer-id))))))

(deftest devnet-snap-pivot-falls-forward-without-penalizing-pruned-state
  (:layer :integration :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (peer-id "snap-peer-with-only-recent-state")
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex peer-id :peer :peer :request-queue :queue))
         (old-root (make-hash32 (make-byte-vector 32 :initial-element 1)))
         (source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000063"))
         (parent-root
           (progn
             (state-db-set-account
              source-state address (make-state-account :balance 9))
             (state-db-root source-state)))
         (target-root (make-hash32 (make-byte-vector 32 :initial-element 3)))
         (old
           (make-block-header :number 100 :gas-limit 30000000
                              :state-root old-root))
         (parent
           (make-block-header :number 163 :gas-limit 30000000
                              :state-root parent-root))
         (target
           (make-block-header :number 164 :gas-limit 30000000
                              :state-root target-root))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            source-database source-state))
         (account-range
           (ethereum-lisp.snap:snap-state-backend-account-range backend))
         (probes '())
         (logs '())
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range
            (lambda (request)
              (let ((root
                      (make-hash32
                       (ethereum-lisp.snap:snap-get-account-range-root
                        request))))
                (push root probes)
                (if (hash32= root old-root)
                    (ethereum-lisp.snap:make-snap-account-range
                     (ethereum-lisp.snap:snap-get-account-range-id request)
                     '() '())
                    (funcall account-range request)))))))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (callback-node &key snap-only-p)
              (is (eq node callback-node))
              (is snap-only-p)
              (list entry)))
      (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
            (lambda (callback-entry)
              (is (eq entry callback-entry))
              source))
     (cons 'ethereum-lisp.cli::devnet-peer-manager-log
            (lambda (callback-node name &rest fields)
              (is (eq node callback-node))
              (push (cons name fields) logs))))
     (lambda ()
       (handler-case
           (multiple-value-bind (selected-entry pivot selected-tail)
               (ethereum-lisp.cli::devnet-node-select-snap-pivot
                node entry (list old parent target))
             (is (eq entry selected-entry))
             (is (eq parent pivot))
             (is (equal (list parent target) selected-tail)))
         (serious-condition (condition)
           (error "Snap pivot selection failed after probes ~S and logs ~S: ~A"
                  probes logs condition)))))
    (is (= 2 (length probes)))
    (is (hash32= old-root (second probes)))
    (is (hash32= parent-root (first probes)))
    (is (= 1 (length logs)))
    (is (string= "peer.snap.pivot_unavailable" (caar logs)))
    (is (= 0 (ethereum-lisp.cli::devnet-peer-score
              (ethereum-lisp.cli::devnet-node-peer-table node) peer-id)))))

(deftest devnet-snap-full-import-pruning-falls-forward-once-without-exit
  (:layer :integration :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (target (make-hash32 (make-byte-vector 32 :initial-element 91)))
         (attempts '())
         (logs '())
         (fallback-succeeds-p t))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons
       'ethereum-lisp.cli::devnet-node-snap-sync-pivot-attempt
       (lambda (seen-node seen-target fallback-only-p)
         (is (eq node seen-node))
         (is (hash32= target seen-target))
         (push fallback-only-p attempts)
         (if (and fallback-only-p fallback-succeeds-p)
             1
             (ethereum-lisp.snap-sync:snap-sync-state-unavailable
              "storage-range"))))
      (cons
       'ethereum-lisp.cli::devnet-peer-manager-log
       (lambda (seen-node name &rest fields)
         (is (eq node seen-node))
         (push (cons name fields) logs))))
     (lambda ()
       (is (= 1
              (ethereum-lisp.cli::devnet-node-snap-sync-target node target)))
       (is (equal '(nil t) (nreverse attempts)))
       (is (= 1 (count "peer.snap.pivot_fallback" logs
                       :test #'string= :key #'car)))
       ;; If the target-parent state is unavailable too, the same two bounded
       ;; attempts become a coordinator-retry condition, never a fatal worker
       ;; error. This is the live Hoodi failure mode that used to stop the node.
       (setf fallback-succeeds-p nil
             attempts nil
             logs nil)
       (signals ethereum-lisp.eth-sync:eth-sync-multi-peer-error
         (ethereum-lisp.cli::devnet-node-snap-sync-target node target))
       (is (equal '(nil t) (nreverse attempts)))
       (is (= 1 (count "peer.snap.pivot_fallback" logs
                       :test #'string= :key #'car)))))))

(deftest devnet-sync-coordinator-refreshes-after-snap-source-exhaustion
  (:layer :integration :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (passes 0)
         (logs '())
         (local-failure-p nil))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons
       'ethereum-lisp.cli::devnet-node-multi-sync-pass
       (lambda (seen-node)
         (is (eq node seen-node))
         (incf passes)
         (cond
           (local-failure-p
            (ethereum-lisp.validation:storage-fail
             "Simulated local snap database failure"))
           ((= passes 1)
            (error
             'ethereum-lisp.snap-sync:snap-sync-sources-exhausted
             :phase :account-ranges
             :failures
             (list
              (make-condition
               'simple-error
               :format-control "Retired source generation"
               :format-arguments nil))))
           (t 7))))
      (cons
       'ethereum-lisp.cli::devnet-peer-manager-log
       (lambda (seen-node name &rest fields)
         (is (eq node seen-node))
         (push (cons name fields) logs))))
     (lambda ()
       ;; The first finite source snapshot is contained.  A later pass reaches
       ;; the shipped sync entry point again and can use the replacement peers.
       (is (null
            (ethereum-lisp.cli::devnet-node-sync-coordinator-pass node)))
       (is (= 7
              (ethereum-lisp.cli::devnet-node-sync-coordinator-pass node)))
       (is (= 2 passes))
       (is (= 1 (length logs)))
       (is (string= "peer.snap.sources_retry" (caar logs)))
       (flet ((field (name)
                (loop for (key value) on (cdar logs) by #'cddr
                      when (string= key name) return value)))
         (is (eq :account-ranges (field "phase")))
         (is (= 1 (field "failures"))))
       ;; Positive fail-closed control: only the explicit remote-source type is
       ;; retryable.  A local durable-store fault still crosses the production
       ;; coordinator pass and reaches the node supervisor.
       (setf local-failure-p t)
       (signals ethereum-lisp.validation:storage-error
         (ethereum-lisp.cli::devnet-node-sync-coordinator-pass node))))
    (is (= 3 passes))))

(deftest devnet-range-announcement-wakes-coordinator-without-lost-race
  (:layer :integration :module :p2p)
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0 :p2p-port 0))
         (shutdown
           (ethereum-lisp.cli:make-devnet-shutdown-controller))
         (lock
           (sb-thread:make-mutex :name "test-sync-announcement-wakeup"))
         (changed
           (sb-thread:make-waitqueue :name "test-sync-announcement-wakeup"))
         (release-first-pass-p nil)
         (passes 0)
         (coordinator-error nil)
         (thread nil)
         (peer-status
           (ethereum-lisp.eth-wire:make-eth-status
            :version 69 :earliest-block 0 :latest-block 10
            :latest-block-hash
            (make-byte-vector 32 :initial-element 1)))
         (peer
           (ethereum-lisp.eth-sync::%make-eth-peer
            :eth-version 69 :remote-status peer-status))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "sync-announcement-peer" :peer peer)))
    (labels ((wait-until (predicate timeout-seconds)
               (sb-thread:with-mutex (lock)
                 (unless (funcall predicate)
                   (sb-thread:condition-wait
                    changed lock :timeout timeout-seconds))
                 (funcall predicate)))
             (run-pass (seen-node)
               (is (eq node seen-node))
               (sb-thread:with-mutex (lock)
                 (incf passes)
                 (sb-thread:condition-broadcast changed)
                 (when (= passes 1)
                   (loop until release-first-pass-p
                         do (sb-thread:condition-wait changed lock)))))
             (release-first-pass ()
               (sb-thread:with-mutex (lock)
                 (setf release-first-pass-p t)
                 (sb-thread:condition-broadcast changed))))
      (unwind-protect
           (progn
             (setf thread
                   (ethereum-lisp.cli::devnet-start-sync-coordinator-thread
                    node shutdown
                    (lambda (condition)
                      (sb-thread:with-mutex (lock)
                        (setf coordinator-error condition)
                        (sb-thread:condition-broadcast changed)))
                    :pass-function #'run-pass
                    ;; If the notification wiring is absent, the second pass
                    ;; cannot happen during this test's bounded wait.
                    :poll-interval-seconds 30d0))
             (is (not (null thread)))
             (is (wait-until (lambda () (= passes 1)) 2d0))
             ;; Drive the shipped session-admission boundary.  The stub replaces
             ;; only socket pumping; production installs the peer callback, then
             ;; the real gossip handler validates and applies the range update.
             ;; It runs while the first pass is still active, proving the event
             ;; remains pending until the coordinator reaches its wait.
             (devnet-peer-sync-call-with-function-overrides
              (list
               (cons
                'ethereum-lisp.cli::devnet-peer-session-readable-function
                (lambda (seen-peer)
                  (is (eq peer seen-peer))
                  (lambda (timeout) (declare (ignore timeout)) nil)))
               (cons
                'ethereum-lisp.eth-sync:eth-peer-run-session
                (lambda (seen-peer &rest arguments)
                  (declare (ignore arguments))
                  (is (eq peer seen-peer))
                  (is
                   (ethereum-lisp.eth-sync:eth-peer-gossip-message
                    seen-peer
                    ethereum-lisp.eth-wire:+eth-message-block-range-update+
                    (ethereum-lisp.eth-wire:encode-eth-block-range-update
                     (ethereum-lisp.eth-wire:make-eth-block-range
                      5 20
                      (make-byte-vector 32 :initial-element 2))))))))
              (lambda ()
                (ethereum-lisp.cli::devnet-peer-run-session
                 node nil shutdown
                 (lambda (socket)
                   (declare (ignore socket))
                   (values peer entry nil)))))
             (is (= 20
                    (ethereum-lisp.eth-wire:eth-status-latest-block
                     peer-status)))
             (release-first-pass)
             (is (wait-until (lambda () (>= passes 2)) 1d0))
             (is (null coordinator-error))
             ;; The coordinator is now idle on its 30-second fallback.  The
             ;; shutdown controller's registered wake closes it promptly.
             (ethereum-lisp.cli:devnet-shutdown-request shutdown)
             (let ((joined
                     (sb-thread:join-thread
                      thread :timeout 2 :default :timeout)))
               (is (not (eq :timeout joined)))
               (when (eq :timeout joined)
                 (sb-thread:terminate-thread thread)
                 (sb-thread:join-thread thread))))
        (release-first-pass)
        (ethereum-lisp.cli:devnet-shutdown-request shutdown)
        (when (and thread (sb-thread:thread-alive-p thread))
          (sb-thread:terminate-thread thread)
          (sb-thread:join-thread thread)))))
  #-sbcl
  (is t))

(deftest devnet-peer-gap-fill-retries-a-buffered-target-with-known-parent
  (:layer :integration :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (genesis
           (ethereum-lisp.cli::devnet-node-genesis-block node))
         (target
           (make-block
            :header
            (make-block-header
             :parent-hash (block-hash genesis)
             :number 1
             :gas-limit 30000000
             :timestamp 1)))
         (fill-calls 0)
         (retried-targets '()))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons
       'ethereum-lisp.cli::devnet-node-sync-targets
       (lambda (seen-node)
         (is (eq node seen-node))
         (list target)))
      (cons
       'ethereum-lisp.cli::devnet-node-forkchoice-sync-targets
       (lambda (seen-node)
         (is (eq node seen-node))
         nil))
      (cons
       'ethereum-lisp.eth-sync:eth-sync-fill-gap
       (lambda (peer target-hash known-hash-p import-block &rest arguments)
         (declare (ignore arguments))
         (is (eq :peer peer))
         (is (bytes= target-hash
                     (hash32-bytes (block-hash genesis))))
         (is (functionp known-hash-p))
         (is (functionp import-block))
         (incf fill-calls)
         ;; The parent was supplied by another path after TARGET was buffered.
         0))
      (cons
       'ethereum-lisp.cli::devnet-peer-sync-import-block
       (lambda (seen-node block &key peer-id require-valid-p)
         (is (eq node seen-node))
         (is (null peer-id))
         (is require-valid-p)
         (push block retried-targets)))
      (cons
       'ethereum-lisp.cli::devnet-peer-manager-log
       (lambda (&rest arguments)
         (declare (ignore arguments)))))
     (lambda ()
       (is (= 1
              (ethereum-lisp.cli::devnet-peer-fill-sync-gaps
               node :peer)))))
    (is (= 1 fill-calls))
    (is (= 1 (length retried-targets)))
    (is (hash32= (block-hash target)
                 (block-hash (first retried-targets))))))

(deftest devnet-multi-sync-defers-a-large-newpayload-gap-until-forkchoice
  (:layer :integration :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (head-hash
           (chain-store-canonical-hash
            (ethereum-lisp.cli::devnet-node-store node) 0))
         (target-hash (make-hash32 (make-byte-vector 32 :initial-element 9)))
         (source-calls 0)
         (download-calls 0))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons
       'ethereum-lisp.cli::devnet-node-forkchoice-sync-targets
       (lambda (seen-node)
         (is (eq node seen-node))
         nil))
      (cons
       'ethereum-lisp.cli::devnet-node-consensus-forward-target
       (lambda (seen-node)
         (is (eq node seen-node))
         (values 0 head-hash 1000 target-hash)))
      (cons
       'ethereum-lisp.cli::devnet-node-live-sync-entries
       (lambda (seen-node &key snap-only-p)
         (is (eq node seen-node))
         (is snap-only-p)
         (list :snap-peer)))
      (cons
       'ethereum-lisp.cli::devnet-node-sync-peer-sources
       (lambda (seen-node)
         (declare (ignore seen-node))
         (incf source-calls)
         (list :source)))
      (cons
       'ethereum-lisp.eth-sync:eth-sync-download-blocks-multi
       (lambda (&rest arguments)
         (declare (ignore arguments))
         (incf download-calls))))
     (lambda ()
       (is (null (ethereum-lisp.cli::devnet-node-multi-sync-pass node)))))
    (is (= 0 source-calls))
    (is (= 0 download-calls))))

(deftest devnet-peer-gap-fill-only-swallows-typed-peer-failures
  (:layer :integration :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (genesis
           (ethereum-lisp.cli::devnet-node-genesis-block node))
         (target
           (make-block
            :header
            (make-block-header
             :parent-hash (block-hash genesis)
             :number 1
             :gas-limit 30000000
             :timestamp 1)))
         (fill-calls 0)
         (import-calls 0)
         (failure-logs 0)
         (mode :peer-failure))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons
       'ethereum-lisp.cli::devnet-node-sync-targets
       (lambda (seen-node)
         (is (eq node seen-node))
         (list target)))
      (cons
       'ethereum-lisp.cli::devnet-node-forkchoice-sync-targets
       (lambda (seen-node)
         (is (eq node seen-node))
         nil))
      (cons
       'ethereum-lisp.eth-sync:eth-sync-fill-gap
       (lambda (peer target-hash known-hash-p import-block &rest arguments)
         (declare (ignore target-hash known-hash-p arguments))
         (is (eq :peer peer))
         (incf fill-calls)
         (ecase mode
           (:peer-failure
            (error 'ethereum-lisp.eth-sync:eth-sync-backfill-peer-error
                   :format-control "Injected peer branch miss"
                   :format-arguments nil))
           (:storage-failure
            ;; Drive the real callback passed by DEVNET-PEER-FILL-SYNC-GAPS.  A
            ;; durability failure below must cross its handler unchanged.
            (funcall import-block target)))))
      (cons
       'ethereum-lisp.cli::devnet-peer-sync-import-block
       (lambda (seen-node block &key peer-id require-valid-p)
         (is (eq node seen-node))
         (is (eq target block))
         (is (null peer-id))
         (is require-valid-p)
         (incf import-calls)
         (ethereum-lisp.validation:storage-fail
          "Injected candidate durability failure")))
      (cons
       'ethereum-lisp.cli::devnet-peer-manager-log
       (lambda (&rest arguments)
         (declare (ignore arguments))
         (incf failure-logs))))
     (lambda ()
       ;; A typed peer branch miss is local to this target.
       (is (= 0
              (ethereum-lisp.cli::devnet-peer-fill-sync-gaps node :peer)))
       (setf mode :storage-failure)
       ;; A local import/durability failure belongs to the session supervisor.
       (signals ethereum-lisp.validation:storage-error
         (ethereum-lisp.cli::devnet-peer-fill-sync-gaps node :peer))))
    (is (= 2 fill-calls))
    (is (= 1 import-calls))
    (is (= 1 failure-logs))))

(deftest devnet-peer-sync-worker-syncs-into-a-node-store-over-a-socket
  (:requires-local-sockets t)
  ;; Drive the actual CLI peer-sync worker: it dials a loopback peer serving a
  ;; produced chain and imports it into a real devnet node's candidate store.
  ;; A peer never advances the post-Merge canonical head. Helpers and the Paris
  ;; genesis come from eth-sync-tests.lisp, which loads earlier.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (config (ethereum-lisp.cli::devnet-node-config node))
         (genesis-block (ethereum-lisp.cli::devnet-node-genesis-block node))
         (store (ethereum-lisp.cli::devnet-node-store node))
         (produced (coerce (eth-sync-produce-empty-blocks genesis-block config 3)
                           'vector))
         (genesis-hash (hash32-bytes (block-hash genesis-block)))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp)))
    (setf (sb-bsd-sockets:sockopt-reuse-address listener) t)
    (unwind-protect
         (progn
           (sb-bsd-sockets:socket-bind
            listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
           (sb-bsd-sockets:socket-listen listener 1)
           (multiple-value-bind (address port)
               (sb-bsd-sockets:socket-name listener)
             (declare (ignore address))
             (let ((server-error nil))
               (let ((server-thread
                       (sb-thread:make-thread
                        (lambda ()
                          (handler-case
                              (let* ((cs (sb-bsd-sockets:socket-accept listener))
                                     (stream (p2p-binary-socket-stream cs))
                                     (connection (rlpx-accept-stream stream server-static))
                                     (peer (eth-peer-connect
                                            connection
                                            (make-devp2p-hello
                                             :client-id "srv"
                                             :capabilities
                                             (list (make-devp2p-capability "eth" 68))
                                             :node-id server-static-pub)
                                            (eth-build-status config genesis-hash
                                                              3 0 genesis-hash 0))))
                                (eth-sync-serve-block-list peer produced))
                            (error (condition) (setf server-error condition))))
                        :name "devnet-peer-sync-test-server")))
                 ;; The worker dials the enode and imports into the node store.
                 (let ((enode (enode-url (node-id-from-private-key server-static)
                                         "127.0.0.1" port)))
                   (ethereum-lisp.cli::devnet-peer-sync-one node enode client-static))
                 (sb-thread:join-thread server-thread)
                 (when server-error
                   (error "peer-sync server side failed: ~A" server-error))
                 ;; All candidates executed, but only Engine forkchoice may
                 ;; publish the post-Merge canonical view.
                 (is (= 0 (chain-store-head-number store)))
                 (is (not (null (chain-store-known-block
                                 store (block-hash (aref produced 2))))))
                 (is (chain-store-state-available-p
                      store (block-hash (aref produced 2))))
                 (let* ((tip (block-hash (aref produced 2)))
                        (zero (hash32-to-hex (zero-hash32)))
                        (response
                          (engine-rpc-handle-request
                           (list
                            (cons "jsonrpc" "2.0")
                            (cons "id" 81)
                            (cons "method" "engine_forkchoiceUpdatedV1")
                            (cons
                             "params"
                             (list
                              (list
                               (cons "headBlockHash" (hash32-to-hex tip))
                               (cons "safeBlockHash" zero)
                               (cons "finalizedBlockHash" zero)))))
                           store config)))
                   (is (null (cdr (assoc "error" response :test #'string=))))
                   (is (= 3 (chain-store-head-number store))))))))
      (ignore-errors (sb-bsd-sockets:socket-close listener)))))

(defun devnet-peer-sync-serve-and-ask (peer blocks request-id)
  "Serve the syncing peer's header and body requests from BLOCKS while awaiting
our own BlockHeaders reply for REQUEST-ID, and return that reply.

The interleaving is the point: both sides have a request outstanding at once, so
this only terminates if the node under test answers ours while it waits for its
own. Exactly three messages arrive — its two requests and its one reply — so the
loop cannot block on a message that never comes."
  (let ((reply nil)
        (answered-headers nil)
        (answered-bodies nil))
    (loop
      (when (and reply answered-headers answered-bodies)
        (return reply))
      (multiple-value-bind (eth-id payload) (eth-peer-read peer)
        (cond
          ((= eth-id ethereum-lisp.eth-wire:+eth-message-get-block-headers+)
           (let* ((request (ethereum-lisp.eth-wire:decode-eth-get-block-headers
                            payload))
                  (origin (ethereum-lisp.eth-wire:eth-get-block-headers-origin-number
                           request))
                  (amount (ethereum-lisp.eth-wire:eth-get-block-headers-amount
                           request))
                  (headers (loop for n from origin below (+ origin amount)
                                 when (<= 1 n (length blocks))
                                   collect (block-header (aref blocks (1- n))))))
             (eth-peer-send
              peer ethereum-lisp.eth-wire:+eth-message-block-headers+
              (ethereum-lisp.eth-wire:encode-eth-block-headers
               (ethereum-lisp.eth-wire:eth-get-block-headers-request-id request)
               headers))
             (setf answered-headers t)))
          ((= eth-id ethereum-lisp.eth-wire:+eth-message-get-block-bodies+)
           (multiple-value-bind (rid hashes)
               (ethereum-lisp.eth-wire:decode-eth-get-block-bodies payload)
             (eth-peer-send
              peer ethereum-lisp.eth-wire:+eth-message-block-bodies+
              (ethereum-lisp.eth-wire:encode-eth-block-bodies
               rid (mapcar (lambda (hash)
                             (ethereum-lisp.eth-wire:block-eth-body
                              (find-if (lambda (block)
                                         (bytes= hash (hash32-bytes
                                                       (block-hash block))))
                                       blocks)))
                           hashes)))
             (setf answered-bodies t)))
          ((= eth-id ethereum-lisp.eth-wire:+eth-message-block-headers+)
           (multiple-value-bind (id headers)
               (ethereum-lisp.eth-wire:decode-eth-block-headers payload)
             (when (= id request-id)
               (setf reply (list headers))))))))))

(deftest devnet-peer-sync-worker-answers-the-peer-while-it-syncs
  (:requires-local-sockets t)
  ;; The CLI worker's connection is not one-way: while it downloads, it answers
  ;; the remote's own requests out of the node's store. Here the remote asks for
  ;; genesis, which is all the node has when the session opens.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (config (ethereum-lisp.cli::devnet-node-config node))
         (genesis-block (ethereum-lisp.cli::devnet-node-genesis-block node))
         (store (ethereum-lisp.cli::devnet-node-store node))
         (produced (coerce (eth-sync-produce-empty-blocks genesis-block config 3)
                           'vector))
         (genesis-hash (hash32-bytes (block-hash genesis-block)))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (served nil)
         (listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp)))
    (setf (sb-bsd-sockets:sockopt-reuse-address listener) t)
    (unwind-protect
         (progn
           (sb-bsd-sockets:socket-bind
            listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
           (sb-bsd-sockets:socket-listen listener 1)
           (multiple-value-bind (address port)
               (sb-bsd-sockets:socket-name listener)
             (declare (ignore address))
             (let ((server-error nil))
               (let ((server-thread
                       (sb-thread:make-thread
                        (lambda ()
                          (handler-case
                              (let* ((cs (sb-bsd-sockets:socket-accept listener))
                                     (stream (p2p-binary-socket-stream cs))
                                     (connection (rlpx-accept-stream stream
                                                                     server-static))
                                     (peer (eth-peer-connect
                                            connection
                                            (make-devp2p-hello
                                             :client-id "srv"
                                             :capabilities
                                             (list (make-devp2p-capability "eth" 68))
                                             :node-id server-static-pub)
                                            (eth-build-status config genesis-hash
                                                              3 0 genesis-hash 0)))
                                     (request-id (eth-peer-next-request-id peer)))
                                ;; Ask before serving, so both sides are waiting.
                                (eth-peer-send
                                 peer
                                 ethereum-lisp.eth-wire:+eth-message-get-block-headers+
                                 (ethereum-lisp.eth-wire:encode-eth-get-block-headers
                                  (ethereum-lisp.eth-wire:make-eth-get-block-headers
                                   :request-id request-id :origin-number 0
                                   :amount 1)))
                                (setf served
                                      (devnet-peer-sync-serve-and-ask
                                       peer produced request-id)))
                            (error (condition) (setf server-error condition))))
                        :name "devnet-peer-serve-test-server")))
                 (let ((enode (enode-url (node-id-from-private-key server-static)
                                         "127.0.0.1" port)))
                   (ethereum-lisp.cli::devnet-peer-sync-one node enode client-static))
                 (sb-thread:join-thread server-thread)
                 (when server-error
                   (error "peer-serve server side failed: ~A" server-error))
                 ;; The node answered from its store: one header, the genesis it
                 ;; was started with.
                 (is (not (null served)))
                 (let ((headers (first served)))
                   (is (= 1 (length headers)))
                   (is (= 0 (block-header-number (first headers))))
                   (is (bytes= genesis-hash
                               (hash32-bytes (block-header-hash (first headers))))))
                 ;; And its own candidate download still completed without
                 ;; giving a peer canonical authority.
                 (is (= 0 (chain-store-head-number store)))
                 (is (chain-store-state-available-p
                      store (block-hash (aref produced 2))))))))
      (ignore-errors (sb-bsd-sockets:socket-close listener)))))

(deftest devnet-peer-sync-worker-pools-a-gossiped-transaction
  (:requires-local-sockets t)
  ;; A transaction pushed by a peer goes through the node's real admission path
  ;; into its real pool, under the store guard, while the worker is syncing.
  ;; The peer serves no blocks, so the download ends at once and only the
  ;; gossip is under test.
  (let ((genesis-path
          (devnet-cli-temp-path "ethereum-lisp-devnet-gossip-genesis" "json")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file
            genesis-path (devnet-cli-funded-txpool-genesis-json))
           (let* ((node (ethereum-lisp.cli:make-devnet-node
                         :genesis-path (namestring genesis-path)
                         :port 0 :public-port 0))
                  (config (ethereum-lisp.cli::devnet-node-config node))
                  (store (ethereum-lisp.cli::devnet-node-store node))
                  (genesis-block (ethereum-lisp.cli::devnet-node-genesis-block node))
                  (genesis-hash (hash32-bytes (block-hash genesis-block)))
                  (transaction (devnet-cli-txpool-transaction
                                config 0 +devnet-cli-txpool-pending-gas-price+))
                  (server-static
                   #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
                  (client-static
                   #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
                  (server-static-pub (secp256k1-private-key-public-key
                                      server-static))
                  (listener (make-instance 'sb-bsd-sockets:inet-socket
                                           :type :stream :protocol :tcp)))
             ;; Not in the pool before the peer offers it.
             (is (null (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                        store (transaction-hash transaction))))
             (setf (sb-bsd-sockets:sockopt-reuse-address listener) t)
             (unwind-protect
                  (progn
                    (sb-bsd-sockets:socket-bind
                     listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
                    (sb-bsd-sockets:socket-listen listener 1)
                    (multiple-value-bind (address port)
                        (sb-bsd-sockets:socket-name listener)
                      (declare (ignore address))
                      (let ((server-error nil))
                        (let ((server-thread
                                (sb-thread:make-thread
                                 (lambda ()
                                   (handler-case
                                       (let* ((cs (sb-bsd-sockets:socket-accept
                                                   listener))
                                              (stream (p2p-binary-socket-stream cs))
                                              (connection (rlpx-accept-stream
                                                           stream server-static))
                                              (peer (eth-peer-connect
                                                     connection
                                                     (make-devp2p-hello
                                                      :client-id "srv"
                                                      :capabilities
                                                      (list (make-devp2p-capability
                                                             "eth" 68))
                                                      :node-id server-static-pub)
                                                     (eth-build-status
                                                      config genesis-hash 0 0
                                                      genesis-hash 0))))
                                         ;; Push the transaction, then end the
                                         ;; node's download with no headers.
                                         (eth-peer-send
                                          peer
                                          ethereum-lisp.eth-wire:+eth-message-transactions+
                                          (ethereum-lisp.eth-wire:encode-eth-transactions
                                           (list transaction)))
                                         (multiple-value-bind (eth-id payload)
                                             (eth-peer-read peer)
                                           (declare (ignore eth-id))
                                           (let ((request
                                                   (ethereum-lisp.eth-wire:decode-eth-get-block-headers
                                                    payload)))
                                             (eth-peer-send
                                              peer
                                              ethereum-lisp.eth-wire:+eth-message-block-headers+
                                              (ethereum-lisp.eth-wire:encode-eth-block-headers
                                               (ethereum-lisp.eth-wire:eth-get-block-headers-request-id
                                                request)
                                               '())))))
                                     (error (condition)
                                       (setf server-error condition))))
                                 :name "devnet-gossip-test-server")))
                          (let ((enode (enode-url
                                        (node-id-from-private-key server-static)
                                        "127.0.0.1" port)))
                            (ethereum-lisp.cli::devnet-peer-sync-one
                             node enode client-static))
                          (sb-thread:join-thread server-thread)
                          (when server-error
                            (error "gossip server side failed: ~A" server-error))
                          ;; The pool took it, by its real hash.
                          (let ((pooled
                                  (ethereum-lisp.txpool:engine-payload-store-pooled-transaction
                                   store (transaction-hash transaction))))
                            (is (not (null pooled)))
                            (is (bytes= (transaction-encoding transaction)
                                        (transaction-encoding pooled))))))))
               (ignore-errors (sb-bsd-sockets:socket-close listener)))))
      (when (probe-file genesis-path)
        (delete-file genesis-path)))))

(deftest devnet-cli-bootnodes-option-accumulates-enodes
  (let* ((enode-a (concatenate 'string "enode://"
                               (make-string 128 :initial-element #\a)
                               "@127.0.0.1:30303"))
         (enode-b (concatenate 'string "enode://"
                               (make-string 128 :initial-element #\c)
                               "@10.0.0.2:30304"))
         (options (ethereum-lisp.cli::devnet-cli-options
                   (list "devnet" "--bootnodes" enode-a "--bootnodes" enode-b
                         "--no-serve"))))
    ;; Repeated --bootnodes flags accumulate in command-line order and land on
    ;; the node as devnet-node-bootnodes.
    (is (equal (list enode-a enode-b) (getf options :bootnodes)))
    (is (null (getf (ethereum-lisp.cli::devnet-cli-options
                     (list "devnet" "--no-serve"))
                    :bootnodes)))
    ;; A single comma-separated value (go-ethereum syntax) expands to a list.
    (is (equal (list enode-a enode-b)
               (getf (ethereum-lisp.cli::devnet-cli-options
                      (list "devnet" "--bootnodes"
                            (concatenate 'string enode-a "," enode-b)
                            "--no-serve"))
                     :bootnodes)))
    (signals error
      (ethereum-lisp.cli::devnet-cli-options
       (list "devnet" "--bootnodes" "not-an-enode" "--no-serve")))))

(deftest devnet-cli-public-presets-install-bootnodes-and-nodiscover-is-real
  (:layer :unit :module :cli)
  (let* ((defaults
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet" "--hoodi" "--no-serve")))
         (disabled
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet" "--hoodi" "--nodiscover" "--bootnodes" ""
                  "--no-serve")))
         (reenabled
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet" "--hoodi" "--nodiscover=false" "--no-serve"))))
    (is (= 3 (length (getf defaults :bootnodes))))
    (is (= 30303 (getf defaults :p2p-port)))
    (is (getf defaults :discovery-enabled-p))
    ;; Explicit empty bootnodes override the public preset rather than being
    ;; mistaken for an absent option and silently refilled.
    (is (null (getf disabled :bootnodes)))
    (is (not (getf disabled :discovery-enabled-p)))
    (is (getf reenabled :discovery-enabled-p))))

(deftest devnet-nodiscover-starts-neither-discovery-direction
  (:layer :integration :module :p2p)
  (let* ((bootnode
           (concatenate 'string "enode://"
                        (make-string 128 :initial-element #\a)
                        "@127.0.0.1:30303"))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path +devnet-cli-genesis-fixture+
            :p2p-port 30303
            :bootnodes (list bootnode)
            :node-key 1
            :discovery-enabled-p nil))
         (shutdown (ethereum-lisp.cli:make-devnet-shutdown-controller)))
    ;; Both have positive controls in p2p-node-table-tests: enabled nodes create
    ;; real worker threads and the responder binds a UDP socket.
    (is (null (ethereum-lisp.cli::devnet-start-discovery-thread
               node shutdown (lambda (condition) (error condition)))))
    (is (null (ethereum-lisp.cli:devnet-start-discovery-server-thread
               node shutdown (lambda (condition) (error condition)))))))

(deftest devnet-cli-nat-and-netrestrict-reach-the-live-node
  (:layer :integration :module :p2p)
  ;; Parsing these flags is not enough: both policies affect the running peer
  ;; boundary and must survive the CLI-to-node construction handoff.  In
  ;; particular, silently dropping extip would advertise loopback in our enode
  ;; and ENR even though the operator explicitly supplied a public address.
  (let* ((options
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet" "--genesis" +devnet-cli-genesis-fixture+
                  "--port" "30303"
                  "--nat" "extip:203.0.113.9"
                  "--netrestrict" "10.0.0.0/8,192.0.2.0/24"
                  "--no-serve")))
         (node
           (ethereum-lisp.cli::devnet-cli-make-node
            options +devnet-cli-genesis-fixture+ nil
            ethereum-lisp.telemetry:*telemetry-sink*)))
    (is (eq :extip
            (ethereum-lisp.nat:nat-policy-mode
             (ethereum-lisp.cli::devnet-node-nat-policy node))))
    (is (string= "203.0.113.9"
                 (ethereum-lisp.cli::devnet-node-advertised-host node)))
    (is (search "@203.0.113.9:30303"
                (ethereum-lisp.cli::devnet-node-enode node)))
    (is (equal '("10.0.0.0/8" "192.0.2.0/24")
               (ethereum-lisp.cli::devnet-peer-table-netrestrict
                (ethereum-lisp.cli:devnet-node-peer-table node))))))

(deftest devnet-datadir-persists-node-identity-and-monotonic-enr-sequence
  (:layer :integration :module :cli)
  (let* ((datadir (devnet-cli-temp-directory "ethereum-lisp-node-identity"))
         (args (list "devnet" "--genesis" +devnet-cli-genesis-fixture+
                     "--datadir" (namestring datadir) "--port" "30303"
                     "--no-serve")))
    (unwind-protect
         (labels ((open-node ()
                    (let ((options
                            (ethereum-lisp.cli::devnet-cli-options args)))
                      (ethereum-lisp.cli::call-with-devnet-cli-datadir-lock
                       (getf options :datadir-path)
                       (lambda ()
                         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
                          (lambda ()
                            (ethereum-lisp.cli::devnet-cli-make-node
                             options +devnet-cli-genesis-fixture+ nil
                             ethereum-lisp.telemetry:*telemetry-sink*))))))))
           (let* ((first (open-node))
                  (key (ethereum-lisp.cli::devnet-node-node-key first))
                  (sequence (ethereum-lisp.cli::devnet-node-record-seq first)))
             (is (= 1 sequence))
             (ethereum-lisp.cli::devnet-node-record-pairs first)
             (setf (ethereum-lisp.cli::devnet-node-p2p-port first) 30304)
             (ethereum-lisp.cli::devnet-node-record-pairs first)
             (is (= 2 (ethereum-lisp.cli::devnet-node-record-seq first)))
             (let ((second (open-node)))
               (is (= key (ethereum-lisp.cli::devnet-node-node-key second)))
               (is (= 3 (ethereum-lisp.cli::devnet-node-record-seq second))))
             (is (probe-file
                  (ethereum-lisp.cli::devnet-cli-datadir-node-key-path datadir)))
             (is (string=
                  "3"
                  (string-trim
                   '(#\Space #\Tab #\Newline #\Return)
                   (devnet-cli-file-string
                    (ethereum-lisp.cli::devnet-cli-datadir-enr-seq-path
                     datadir)))))))
      (uiop:delete-directory-tree datadir
                                  :validate t
                                  :if-does-not-exist :ignore))))

(deftest devnet-eth-72-cell-serving-uses-little-endian-custody-and-flat-groups
  (:layer :unit :module :p2p)
  (let* ((hash (make-byte-vector 32 :initial-element 7))
         (mask (make-byte-vector 16))
         (sidecar
           (make-blob-sidecar
            :blobs (list (make-byte-vector 1) (make-byte-vector 1)))))
    (setf (aref mask 0) #x01
          (aref mask 15) #x80)
    (multiple-value-bind (hashes groups response-mask)
        (ethereum-lisp.cli::devnet-peer-blob-cells-from-reader
         (lambda (requested)
           (and (bytes= requested hash) sidecar))
         (list hash) mask
         :cell-function
         (lambda (blob)
           (declare (ignore blob))
           (values
            (loop for index below 128
                  collect (make-byte-vector 2048 :initial-element index))
            nil)))
      (is (= 1 (length hashes)))
      (is (bytes= hash (first hashes)))
      (is (bytes= mask response-mask))
      (is (= 4 (length (first groups))))
      (is (equal '(0 127 0 127)
                 (mapcar (lambda (cell) (aref cell 0)) (first groups)))))))

(deftest devnet-peer-request-queue-preserves-the-sole-writer-and-errors
  (:layer :integration :module :p2p)
  #+sbcl
  (labels ((queued-p (queue)
             (sb-thread:with-mutex
                 ((ethereum-lisp.cli::devnet-peer-request-queue-lock queue))
               (not (null
                     (ethereum-lisp.cli::devnet-peer-request-queue-pending
                      queue))))))
    (let* ((queue (ethereum-lisp.cli::make-devnet-peer-request-queue))
           (writer sb-thread:*current-thread*)
           (result nil)
           (submitter
             (sb-thread:make-thread
              (lambda ()
                (setf result
                      (multiple-value-list
                       (ethereum-lisp.cli::devnet-peer-request-queue-submit
                        queue
                        (lambda ()
                          (values sb-thread:*current-thread* :first :second))))))
              :name "section5-request-submit-success")))
      (unwind-protect
           (progn
             (wait-for-test-condition
              "queued peer request" 2d0 (lambda () (queued-p queue)))
             (funcall
              (funcall
               (ethereum-lisp.cli::devnet-peer-pending-request queue)))
             (is (not (eq :timeout
                          (sb-thread:join-thread
                           submitter :timeout 2 :default :timeout))))
             (is (eq writer (first result)))
             (is (equal '(:first :second) (rest result))))
        (ethereum-lisp.cli::devnet-peer-request-queue-close queue)))
    (let* ((queue (ethereum-lisp.cli::make-devnet-peer-request-queue))
           (submitted-condition nil)
           (submitter
             (sb-thread:make-thread
              (lambda ()
                (handler-case
                    (ethereum-lisp.cli::devnet-peer-request-queue-submit
                     queue (lambda () (error "injected writer failure")))
                  (serious-condition (condition)
                    (setf submitted-condition condition))))
              :name "section5-request-submit-failure")))
      (unwind-protect
           (progn
             (wait-for-test-condition
              "queued failing peer request" 2d0 (lambda () (queued-p queue)))
             (signals serious-condition
               (funcall
                (funcall
                 (ethereum-lisp.cli::devnet-peer-pending-request queue))))
             (is (not (eq :timeout
                          (sb-thread:join-thread
                           submitter :timeout 2 :default :timeout))))
             (is (typep submitted-condition 'serious-condition)))
        (ethereum-lisp.cli::devnet-peer-request-queue-close queue))))
  #-sbcl
  (is t))

(deftest devnet-cli-nodekeyhex-yields-a-stable-identity
  (let* ((hex "0000000000000000000000000000000000000000000000000000000000000001")
         (options-a (ethereum-lisp.cli::devnet-cli-options
                     (list "devnet" "--nodekeyhex" hex "--no-serve")))
         (options-b (ethereum-lisp.cli::devnet-cli-options
                     (list "devnet" "--nodekeyhex" hex "--no-serve"))))
    ;; The key parses to the scalar and is stable across parses.
    (is (= 1 (getf options-a :node-key)))
    (is (= (getf options-a :node-key) (getf options-b :node-key)))
    ;; Its node id is the public key of scalar 1.
    (is (bytes= (node-id-from-private-key 1)
                (secp256k1-private-key-public-key (getf options-a :node-key))))
    ;; No key given => nil; make-devnet-node then generates one.
    (is (null (getf (ethereum-lisp.cli::devnet-cli-options
                     (list "devnet" "--no-serve"))
                    :node-key)))
    ;; A malformed key is rejected.
    (signals error
      (ethereum-lisp.cli::devnet-cli-options
       (list "devnet" "--nodekeyhex" "not-hex" "--no-serve")))
    ;; A key that is not 32 bytes is rejected.
    (signals error
      (ethereum-lisp.cli::devnet-cli-options
       (list "devnet" "--nodekeyhex" "0xdeadbeef" "--no-serve")))))

(deftest devnet-node-adopts-its-configured-identity
  ;; The dial-claim half of this test went with devnet-node-claim-dial, which the
  ;; dial scheduler replaced: a peer is no longer claimed once and forever, it
  ;; has a cooldown and a failure count (see cli-devnet-dial-tests.lisp).
  (let ((node (ethereum-lisp.cli:make-devnet-node
               :genesis-path +devnet-cli-genesis-fixture+ :port 0
               :node-key #x0102030405060708090a0b0c0d0e0f101112131415161718)))
    (is (= #x0102030405060708090a0b0c0d0e0f101112131415161718
           (ethereum-lisp.cli::devnet-node-node-key node)))
    ;; A node with no configured key still gets a usable identity.
    (is (integerp (ethereum-lisp.cli::devnet-node-node-key
                   (ethereum-lisp.cli:make-devnet-node
                    :genesis-path +devnet-cli-genesis-fixture+ :port 0))))))

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-posix))

#+sbcl
(deftest devnet-cli-write-private-file-is-fail-closed-and-0600
  ;; A JWT secret or node key created with WITH-OPEN-FILE is 0666 & ~umask and
  ;; follows a symlink at the target, so a planted file or link receives the
  ;; secret. DEVNET-CLI-WRITE-PRIVATE-FILE must open with O_EXCL|O_NOFOLLOW and
  ;; mode 0600. Asserting the final mode alone is not sufficient (a restrictive
  ;; umask or a chmod-after-write bug satisfies it too), so the load-bearing
  ;; assertions are that O_EXCL refuses a pre-existing path and O_NOFOLLOW
  ;; refuses a symlink without writing through it.
  (let ((fresh (devnet-cli-temp-path "ethereum-lisp-private-fresh" "hex"))
        (planted (devnet-cli-temp-path "ethereum-lisp-private-planted" "hex"))
        (link (devnet-cli-temp-path "ethereum-lisp-private-link" "hex"))
        (decoy (devnet-cli-temp-path "ethereum-lisp-private-decoy" "hex")))
    (unwind-protect
         (progn
           ;; A fresh path is created with the exact contents and mode 0600.
           (ethereum-lisp.cli::devnet-cli-write-private-file
            fresh
            (lambda (stream) (write-string "deadbeef" stream)))
           (is (string= "deadbeef" (devnet-cli-file-string fresh)))
           (is (= #o600
                  (logand #o777
                          (sb-posix:stat-mode
                           (sb-posix:stat (namestring fresh))))))
           ;; O_EXCL fails closed on a pre-existing regular file rather than
           ;; truncating it and writing the secret into it.
           (devnet-cli-write-temp-file planted "attacker owned")
           (signals error
             (ethereum-lisp.cli::devnet-cli-write-private-file
              planted
              (lambda (stream) (write-string "secret" stream))))
           (is (string= "attacker owned" (devnet-cli-file-string planted)))
           ;; O_NOFOLLOW refuses a symlink: the decoy target is never created,
           ;; proving the secret was not written through the link.
           (sb-posix:symlink (namestring decoy) (namestring link))
           (signals error
             (ethereum-lisp.cli::devnet-cli-write-private-file
              link
              (lambda (stream) (write-string "secret" stream))))
           (is (not (probe-file decoy))))
      (dolist (path (list fresh planted decoy))
        (when (probe-file path)
          (ignore-errors (delete-file path))))
      (ignore-errors (sb-posix:unlink (namestring link))))))

(deftest devnet-cli-non-loopback-engine-bind-requires-jwt
  ;; The Engine HTTP handler enforces JWT auth only inside (when jwt-secret ...):
  ;; with no secret, a non-loopback bind exposes forkchoice and payload control
  ;; to the whole network, so serving must fail closed. Loopback, and a
  ;; configured secret, are both fine.
  (labels ((node (&key (host "127.0.0.1") jwt-secret-path)
             (ethereum-lisp.cli:make-devnet-node
              :genesis-path +devnet-cli-genesis-fixture+
              :host host :port 0
              :jwt-secret-path jwt-secret-path)))
    ;; Loopback classification: 0.0.0.0/:: bind every interface and a bare name
    ;; is treated as routable.
    (is (ethereum-lisp.cli::devnet-cli-loopback-host-p "127.0.0.1"))
    (is (ethereum-lisp.cli::devnet-cli-loopback-host-p "127.0.0.5"))
    (is (ethereum-lisp.cli::devnet-cli-loopback-host-p "localhost"))
    (is (ethereum-lisp.cli::devnet-cli-loopback-host-p "::1"))
    (is (ethereum-lisp.cli::devnet-cli-loopback-host-p "[::1]"))
    (is (not (ethereum-lisp.cli::devnet-cli-loopback-host-p "0.0.0.0")))
    (is (not (ethereum-lisp.cli::devnet-cli-loopback-host-p "192.0.2.10")))
    (is (not (ethereum-lisp.cli::devnet-cli-loopback-host-p "engine.runner")))
    ;; Loopback without a secret is allowed (nil = no error).
    (is (null (ethereum-lisp.cli::devnet-cli-require-engine-authentication
               (node))))
    ;; A non-loopback bind without a secret is refused.
    (signals error
      (ethereum-lisp.cli::devnet-cli-require-engine-authentication
       (node :host "192.0.2.10")))
    ;; A non-loopback bind with a configured secret is allowed.
    (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-engine-jwt" "hex")))
      (unwind-protect
           (progn
             (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
             (is (null
                  (ethereum-lisp.cli::devnet-cli-require-engine-authentication
                   (node :host "192.0.2.10"
                         :jwt-secret-path (namestring jwt-path))))))
        (when (probe-file jwt-path)
          (delete-file jwt-path))))))
