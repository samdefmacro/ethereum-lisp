(in-package #:ethereum-lisp.test)

(deftest devnet-allocation-profile-duration-is-explicit-and-bounded
  (:layer :unit :module :p2p)
  (is (null
       (ethereum-lisp.cli::devnet-parse-allocation-profile-seconds nil)))
  (is (null
       (ethereum-lisp.cli::devnet-parse-allocation-profile-seconds "")))
  (is (null
       (ethereum-lisp.cli::devnet-parse-allocation-profile-seconds "0")))
  (is (= 1
         (ethereum-lisp.cli::devnet-parse-allocation-profile-seconds "1")))
  (is (= 300
         (ethereum-lisp.cli::devnet-parse-allocation-profile-seconds "300")))
  (dolist (invalid '("-1" "301" "1s" "yes"))
    (signals error
      (ethereum-lisp.cli::devnet-parse-allocation-profile-seconds invalid)))
  #+sbcl
  (let* ((secret "peer-secret-must-not-escape")
         (report
           (format nil
                   "Sampled threads:~%~A~%   Self        Total        Cumul~%  Nr Function~%------------------------------------------------------------------------~%   2 SAFE-FUNCTION~%------------------------------------------------------------------------~%elsewhere~%"
                   secret))
         (table
           (ethereum-lisp.cli::devnet-allocation-profile-flat-table report)))
    (is (search "SAFE-FUNCTION" table))
    (is (null (search secret table)))
    (is (null (search "Sampled threads" table)))))

(deftest devnet-discovery-next-crawl-seeds-is-bounded-and-prioritized
  (let ((merged
          (ethereum-lisp.cli::devnet-discovery-next-crawl-seeds
           '("boot-a" "boot-b")
           '("old-a" "new-a" "old-b")
           '("new-a" "new-b" "boot-a"))))
    (is (equal '("boot-a" "boot-b" "new-a" "new-b" "old-a" "old-b")
               merged)))
  (let* ((limit ethereum-lisp.cli::+devnet-discovery-crawl-seed-limit+)
         (discovered
           (loop for index below (+ limit 10)
                 collect (format nil "route-~D" index)))
         (merged
           (ethereum-lisp.cli::devnet-discovery-next-crawl-seeds
            '("boot") nil discovered)))
    (is (= limit (length merged)))
    (is (string= "boot" (first merged)))
    (is (string= "route-0" (second merged)))
    (is (not (member (format nil "route-~D" limit)
                     merged :test #'string=)))))

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

(deftest devnet-peer-range-import-accepts-a-durable-buffered-block
  (:layer :unit :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (block
           (first
            (eth-sync-produce-empty-blocks
             (ethereum-lisp.cli::devnet-node-genesis-block node)
             (ethereum-lisp.cli::devnet-node-config node) 1))))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons
       'ethereum-lisp.block-import:import-p2p-block-candidate
       (lambda (store seen-block config &rest arguments)
         (declare (ignore store config arguments))
         (is (eq block seen-block))
         (values
          (make-payload-status :status +payload-status-accepted+)
          seen-block nil))))
     (lambda ()
       ;; A pre-state forward range is supposed to buffer candidates. Geth does
       ;; the same before its pivot state is available; ACCEPTED is not a fatal
       ;; consensus verdict and must not tear down the node process.
       (multiple-value-bind (status candidate receipts)
           (ethereum-lisp.cli::devnet-peer-sync-import-block
            node block :require-valid-p t)
         (is (string= +payload-status-accepted+
                      (payload-status-status status)))
         (is (eq block candidate))
         (is (null receipts)))))))

(deftest devnet-peer-range-import-still-rejects-an-invalid-block
  (:layer :unit :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (block
           (first
            (eth-sync-produce-empty-blocks
             (ethereum-lisp.cli::devnet-node-genesis-block node)
             (ethereum-lisp.cli::devnet-node-config node) 1))))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons
       'ethereum-lisp.block-import:import-p2p-block-candidate
       (lambda (store seen-block config &rest arguments)
         (declare (ignore store config arguments))
         (values
          (make-payload-status
           :status +payload-status-invalid+
           :validation-error "injected invalid peer block")
          seen-block nil))))
     (lambda ()
       (signals block-validation-error
         (ethereum-lisp.cli::devnet-peer-sync-import-block
          node block :require-valid-p t))))))

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

(deftest devnet-runtime-gc-time-is-reported-in-milliseconds
  (:layer :unit :module :p2p)
  (is (= 0
         (ethereum-lisp.cli::devnet-internal-time-milliseconds 0)))
  (is (= 1000
         (ethereum-lisp.cli::devnet-internal-time-milliseconds
          internal-time-units-per-second)))
  (is (= 1500
         (ethereum-lisp.cli::devnet-internal-time-milliseconds
          (+ internal-time-units-per-second
             (floor internal-time-units-per-second 2))))))

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
         (source-lock
           (sb-thread:make-mutex :name "devnet-snap-test-source-writer"))
         (source
           (flet ((serialized (function)
                    (lambda (request)
                      (sb-thread:with-mutex (source-lock)
                        (funcall function request)))))
             ;; DEVNET-PEER-QUEUED-SNAP-SOURCE provides this sole-writer
             ;; serialization in production. Preserve that contract in the
             ;; direct in-memory test double now that two range workers share
             ;; one logical source.
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range
              (serialized
               (ethereum-lisp.snap:snap-state-backend-account-range backend))
              :storage-ranges
              (serialized
               (ethereum-lisp.snap:snap-state-backend-storage-ranges backend))
              :bytecodes
              (serialized
               (ethereum-lisp.snap:snap-state-backend-bytecodes backend))
              :trie-nodes
              (serialized
               (ethereum-lisp.snap:snap-state-backend-trie-nodes backend)))))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry :id-hex "peer-1"))
         (logs '())
         (profile-events '())
         (import-function
           (fdefinition
            'ethereum-lisp.snap-sync:snap-sync-import-state-multi)))
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
         (push (cons name fields) logs)))
      (cons
       'ethereum-lisp.cli::devnet-maybe-start-allocation-profile
       (lambda () (push :profile-start profile-events)))
      (cons
       'ethereum-lisp.snap-sync:snap-sync-import-state-multi
       (lambda (&rest arguments)
         (push :import-start profile-events)
         (let ((callback (getf arguments :on-storage-profile)))
           (is (functionp callback))
           (funcall
            callback
            (ethereum-lisp.snap-sync::make-snap-sync-storage-profile
             :page-count 2 :slot-count 300 :trie-record-count 400
             :batch-operation-count 450 :logical-batch-bytes 500000
             :completed-task-count 1 :request-ms 20 :proof-ms 30
             :materialize-ms 40 :batch-build-ms 42 :prepare-ms 45 :commit-ms 50
             :writer-idle-ms 60)))
         (apply import-function arguments))))
     (lambda ()
       (is
        (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
         (ethereum-lisp.cli::devnet-node-snap-import-with-failover
          node database pivot-header target-hash)))))
    ;; The profile begins once, before the production importer call. Moving it
    ;; back to the first page callback reverses this witness and leaves a
    ;; zero-page live stall unprofiled.
    (is (equal '(:import-start :profile-start) profile-events))
    (setf logs (nreverse logs))
    (flet ((field (record name)
             (loop for (key value) on (cdr record) by #'cddr
                   when (string= key name) return value)))
      (let ((page-logs
              (remove-if-not
               (lambda (record)
                 (string= "peer.snap.progress" (first record)))
               logs))
            (profile-logs
              (remove-if-not
               (lambda (record)
                 (string= "peer.snap.page_profile" (first record)))
               logs))
            (storage-profile-logs
              (remove-if-not
               (lambda (record)
                 (string= "peer.snap.storage_profile" (first record)))
               logs))
            (heal-logs
              (remove-if-not
               (lambda (record)
                 (string= "peer.snap.heal_progress" (first record)))
               logs))
            (source-logs
              (remove-if-not
               (lambda (record)
                 (string= "peer.snap.sources_refreshed" (first record)))
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
          ;; The synthetic source has no transport queue, so its type-specific
          ;; fields are NIL. A live entry reports positive millisecond values;
          ;; the pool baseline exists for both shapes.
          (is (and (integerp (field record "requestTimeoutMs"))
                   (plusp (field record "requestTimeoutMs"))))
          (dolist (name '("accountTimeoutMs" "storageTimeoutMs"))
            (is (or (null (field record name))
                    (and (integerp (field record name))
                         (plusp (field record name))))))
          ;; Page durability is not state completeness. Byte-capped storage may
          ;; still be mandatory work for the final content-addressed traversal.
          (is (null (field record "completed"))))
        (is (plusp (length profile-logs)))
        (dolist (record profile-logs)
          ;; Runtime memory counters are observational only. They make a live
          ;; Hoodi sample distinguish retained Lisp graphs from RSS which SBCL
          ;; has reclaimed internally but not returned to the kernel.
          (is (and (integerp (field record "dynamicUsageBytes"))
                   (not (minusp (field record "dynamicUsageBytes")))))
          (is (and (integerp (field record "bytesConsed"))
                   (not (minusp (field record "bytesConsed")))))
          (is (and (integerp (field record "gcRunMs"))
                   (not (minusp (field record "gcRunMs")))))
          (is (integerp (field record "totalMs"))))
        (is (= 1 (length storage-profile-logs)))
        (let ((record (first storage-profile-logs)))
          (is (null (field record "peer")))
          (is (= 2 (field record "pages")))
          (is (= 2 (field record "totalPages")))
          (is (= 300 (field record "slots")))
          (is (= 300 (field record "totalSlots")))
          (is (= 500000 (field record "logicalBytes")))
          (is (= 500000 (field record "totalLogicalBytes")))
          (is (= 42 (field record "batchBuildMs")))
          (is (= 45 (field record "prepareMs")))
          (is (= 50 (field record "commitMs")))
          (is (= 60 (field record "writerIdleMs")))
          (is (not (minusp (field record "slotsPerSecond"))))
          (is (not (minusp (field record "logicalBytesPerSecond")))))
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
          (is (= 0 (field record "nodeBytes")))
          (is (= 0 (field record "sampleSeconds")))
          (is (= 0 (field record "processedRate")))
          (is (= 0 (field record "discoveredRate")))
          (is (= 0 (field record "netDrainRate")))
          (is (= 0 (field record "etaSeconds")))
          (is (string= "completed" (field record "etaStatus")))
          (is (string= "high" (field record "etaConfidence"))))
        (is (= 1 (length source-logs)))
        (let ((record (first source-logs)))
          (is (= (block-header-number pivot-header) (field record "pivot")))
          (is (= 1 (field record "added")))
          (is (= 1 (field record "sources"))))))))

(deftest devnet-snap-heal-progress-throttles-intermediate-events
  (:layer :unit :module :p2p)
  (is (ethereum-lisp.cli::devnet-snap-heal-progress-log-due-p nil 100 nil))
  (is (not (ethereum-lisp.cli::devnet-snap-heal-progress-log-due-p
            100 129 nil)))
  (is (ethereum-lisp.cli::devnet-snap-heal-progress-log-due-p 100 130 nil))
  (is (ethereum-lisp.cli::devnet-snap-heal-progress-log-due-p 100 101 t))
  ;; A backwards-adjusted wall clock must not suppress logs indefinitely.
  (is (ethereum-lisp.cli::devnet-snap-heal-progress-log-due-p 100 99 nil)))

(deftest devnet-snap-heal-estimate-requires-stable-net-drain
  (:layer :unit :module :p2p)
  (flet ((sample (at processed frontier)
           (ethereum-lisp.cli::make-devnet-snap-heal-estimate-sample
            at processed frontier)))
    (multiple-value-bind
          (seconds processed-rate discovered-rate net-drain-rate
           eta status confidence)
        (ethereum-lisp.cli::devnet-snap-heal-estimate
         (list (sample 0 1 0)) t)
      (is (= 0 seconds))
      (is (= 0 processed-rate))
      (is (= 0 discovered-rate))
      (is (= 0 net-drain-rate))
      (is (= 0 eta))
      (is (string= "completed" status))
      (is (string= "high" confidence)))
    (multiple-value-bind
          (seconds processed-rate discovered-rate net-drain-rate
           eta status confidence)
        (ethereum-lisp.cli::devnet-snap-heal-estimate
         (list (sample 0 0 100000) (sample 60 120000 90000)) nil)
      (is (= 60 seconds))
      (is (= 2000 processed-rate))
      (is (= 1833 discovered-rate))
      (is (= 167 net-drain-rate))
      (is (null eta))
      (is (string= "warming" status))
      (is (string= "none" confidence)))
    (multiple-value-bind
          (seconds processed-rate discovered-rate net-drain-rate
           eta status confidence)
        (ethereum-lisp.cli::devnet-snap-heal-estimate
         (list (sample 0 0 100000)
               (sample 60 120000 94000)
               (sample 120 240000 88000)
               (sample 180 360000 82000)
               (sample 240 480000 76000)
               (sample 300 600000 70000))
         nil)
      (is (= 300 seconds))
      (is (= 2000 processed-rate))
      (is (= 1900 discovered-rate))
      (is (= 100 net-drain-rate))
      (is (= 700 eta))
      (is (string= "converging" status))
      (is (string= "high" confidence)))
    (multiple-value-bind
          (seconds processed-rate discovered-rate net-drain-rate
           eta status confidence)
        (ethereum-lisp.cli::devnet-snap-heal-estimate
         (list (sample 0 0 100000)
               (sample 100 200000 120000)
               (sample 200 400000 130000)
               (sample 300 600000 90000))
         nil)
      (declare (ignore seconds processed-rate discovered-rate net-drain-rate))
      (is (null eta))
      (is (string= "unstable" status))
      (is (string= "none" confidence)))
    (multiple-value-bind
          (seconds processed-rate discovered-rate net-drain-rate
           eta status confidence)
        (ethereum-lisp.cli::devnet-snap-heal-estimate
         (list (sample 0 0 100000) (sample 300 600000 160000)) nil)
      (declare (ignore seconds processed-rate discovered-rate net-drain-rate))
      (is (null eta))
      (is (string= "dynamic-expansion" status))
      (is (string= "none" confidence)))))

(deftest devnet-snap-heal-estimate-samples-retain-a-bounded-window
  (:layer :unit :module :p2p)
  (flet ((sample (at)
           (ethereum-lisp.cli::make-devnet-snap-heal-estimate-sample
            at at at)))
    (let ((samples
            (ethereum-lisp.cli::devnet-snap-heal-trim-estimate-samples
             (list (sample 0) (sample 100) (sample 200) (sample 400))
             400)))
      (is (= 3 (length samples)))
      (is (= 100
             (ethereum-lisp.cli::devnet-snap-heal-estimate-sample-at
              (first samples)))))))

(deftest devnet-snap-stale-successor-requires-a-newer-forkchoice-target
  (:layer :unit :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (store (ethereum-lisp.cli::devnet-node-store node))
         (old-target (make-hash32 (make-byte-vector 32 :initial-element 80)))
         (at-limit
           (make-block
            :header
            (make-block-header :number 120 :timestamp 120
                               :gas-limit 30000000)))
         (past-limit
           (make-block
            :header
            (make-block-header :number 121 :timestamp 121
                               :gas-limit 30000000)))
         (at-limit-hash (block-hash at-limit))
         (past-limit-hash (block-hash past-limit))
         (latest at-limit-hash))
    (ethereum-lisp.cli::call-with-devnet-node-store-guard
     node
     (lambda ()
       (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
        store at-limit)
       (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
        store past-limit)))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-forkchoice-sync-targets
            (lambda (seen-node)
              (is (eq node seen-node))
              (list latest))))
     (lambda ()
       ;; Exactly 2*64-8 blocks is still inside geth's pivot-relative window.
       (is (null
            (ethereum-lisp.cli::devnet-node-stale-snap-successor
             node old-target 0)))
       (setf latest past-limit-hash)
       (multiple-value-bind (successor number)
           (ethereum-lisp.cli::devnet-node-stale-snap-successor
            node old-target 0)
         (is (hash32= past-limit-hash successor))
         (is (= 121 number)))
       ;; The current target cannot supersede itself regardless of height.
       (setf latest old-target)
       (is (null
            (ethereum-lisp.cli::devnet-node-stale-snap-successor
             node old-target 0)))))))

(deftest devnet-snap-stalled-long-heal-yields-to-a-stale-consensus-target
  (:layer :unit :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (database (make-memory-key-value-database))
         (pivot-header (block-header
                        (ethereum-lisp.cli::devnet-node-genesis-block node)))
         (target-hash
           (make-hash32 (make-byte-vector 32 :initial-element 81)))
         (successor-hash
           (make-hash32 (make-byte-vector 32 :initial-element 82)))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes (lambda (request) (declare (ignore request)))))
         (entry (ethereum-lisp.cli::make-devnet-peer-entry :id-hex "peer-1"))
         (now 100)
         (logs '()))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::unix-time (lambda () now))
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (list entry)))
      (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
            (lambda (seen-entry)
              (is (eq entry seen-entry))
              source))
      (cons 'ethereum-lisp.cli::devnet-node-stale-snap-successor
            (lambda (seen-node seen-target seen-number)
              (is (eq node seen-node))
              (is (hash32= target-hash seen-target))
              (is (= 0 seen-number))
              (values successor-hash 185)))
      (cons 'ethereum-lisp.snap-sync:snap-sync-import-state-multi
            (lambda (seen-database sources &rest arguments)
              (is (eq database seen-database))
              (is (= 1 (length sources)))
              (let ((pooled (first sources)))
                ;; Account ranges and trie healing retain the source identity;
                ;; storage and bytecode are intentionally wrapped by the
                ;; independent live-peer pool.
                (is (eq
                     (ethereum-lisp.snap-sync:snap-sync-source-account-range
                      source)
                     (ethereum-lisp.snap-sync:snap-sync-source-account-range
                      pooled)))
                (is (eq
                     (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                      source)
                     (ethereum-lisp.snap-sync:snap-sync-source-trie-nodes
                      pooled))))
              (let ((range-yield-p (getf arguments :range-yield-p))
                    (yield-p (getf arguments :heal-yield-p))
                    (progress-callback (getf arguments :on-heal-progress)))
                (is (null range-yield-p))
                (is (functionp yield-p))
                (is (functionp progress-callback))
                ;; Productive account-range work pins its authenticated root.
                ;; A clock-driven pivot move would discard the complete range
                ;; plan's zero-TrieNodes completion proof.
                (setf now 129)
                (is (not (funcall yield-p)))
                ;; A large local decode burst can keep the old generic
                ;; progress counter fresh while neither a TrieNodes response
                ;; nor the discovered frontier advances toward closure.
                (setf now 399)
                (funcall
                 progress-callback
                 (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                  :processed-nodes 90000 :reused-nodes 89990
                  :fetched-nodes 10 :request-count 4
                  :response-bytes 4096 :frontier-works 24000 :completed-p nil))
                (setf now 698)
                (is (not (funcall yield-p)))
                ;; Another large local pass with the same remote counters and
                ;; no material net frontier drain must not pin a public pivot
                ;; forever merely because PROCESSED-NODES increased.
                (funcall
                 progress-callback
                 (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                  :processed-nodes 180000 :reused-nodes 179990
                  :fetched-nodes 10 :request-count 4
                  :response-bytes 4096 :frontier-works 24001 :completed-p nil))
                ;; Five minutes without remote response or material closure
                ;; permits a rebase only through the authorized successor.
                (setf now 699)
                (is (funcall yield-p))
                (error 'ethereum-lisp.snap-sync:snap-sync-heal-yielded))))
      (cons 'ethereum-lisp.cli::devnet-peer-manager-log
            (lambda (seen-node name &rest fields)
              (is (eq node seen-node))
              (push (cons name fields) logs))))
     (lambda ()
       (signals ethereum-lisp.snap-sync:snap-sync-heal-yielded
         (ethereum-lisp.cli::devnet-node-snap-import-with-failover
          node database pivot-header target-hash :target-number 64))))
    (let ((record
            (find "peer.snap.target_stale" logs
                  :key #'first :test #'string=)))
      (is record)
      (flet ((field (name)
               (loop for (key value) on (cdr record) by #'cddr
                     when (string= key name) return value)))
        (is (= 64 (field "target")))
        (is (= 185 (field "successor")))
        (is (string= "local-expansion-stalled" (field "reason")))
        (is (string= (hash32-to-hex target-hash) (field "targetHash")))
        (is (string= (hash32-to-hex successor-hash)
                     (field "successorHash")))))))

(deftest devnet-snap-efficient-heal-retains-a-collapsed-source-pool
  (:layer :unit :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (database (make-memory-key-value-database))
         (pivot-header (block-header
                        (ethereum-lisp.cli::devnet-node-genesis-block node)))
         (target-hash
           (make-hash32 (make-byte-vector 32 :initial-element 91)))
         (successor-hash
           (make-hash32 (make-byte-vector 32 :initial-element 92)))
         (entries
           (loop for index below 8
                 collect
                 (ethereum-lisp.cli::make-devnet-peer-entry
                  :id-hex (format nil "peer-~D" index))))
         (sources
           (loop repeat 8
                 collect
                 (ethereum-lisp.snap-sync:make-snap-sync-source
                  :account-range
                  (lambda (request) (declare (ignore request)))
                  :storage-ranges
                  (lambda (request) (declare (ignore request)))
                  :bytecodes
                  (lambda (request) (declare (ignore request)))
                  :trie-nodes
                  (lambda (request) (declare (ignore request))))))
         (entry-sources (mapcar #'cons entries sources))
         (live-entries (copy-list entries))
         (now 100)
         (logs '()))
    ;; A stable small pool never satisfies the relative-collapse precondition.
    (is (not
         (ethereum-lisp.cli::devnet-snap-heal-source-pool-collapsed-p 3 3)))
    (is (not
         (ethereum-lisp.cli::devnet-snap-heal-source-pool-collapsed-p 3 7)))
    (is (ethereum-lisp.cli::devnet-snap-heal-source-pool-collapsed-p 3 8))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::unix-time (lambda () now))
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (copy-list live-entries)))
      (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
            (lambda (entry)
              (or (cdr (assoc entry entry-sources :test #'eq))
                  (error "Missing test source"))))
      (cons 'ethereum-lisp.cli::devnet-node-stale-snap-successor
            (lambda (seen-node seen-target seen-number)
              (is (eq node seen-node))
              (is (hash32= target-hash seen-target))
              (is (= 0 seen-number))
              (values successor-hash 205)))
      (cons 'ethereum-lisp.snap-sync:snap-sync-import-state-multi
            (lambda (seen-database initial-sources &rest arguments)
              (is (eq database seen-database))
              (is (= 8 (length initial-sources)))
              (let ((source-provider (getf arguments :heal-source-provider))
                    (yield-p (getf arguments :heal-yield-p))
                    (progress-callback (getf arguments :on-heal-progress)))
                (is (functionp source-provider))
                (is (functionp yield-p))
                (is (functionp progress-callback))
                (setf live-entries (subseq entries 0 3)
                      now 110)
                (is (= 3 (length (funcall source-provider))))
                ;; A stable recovery clears the collapse window only after
                ;; thirty seconds, then a new collapse begins from that seam.
                (setf live-entries entries
                      now 120)
                (is (= 8 (length (funcall source-provider))))
                (setf now 150)
                (is (= 8 (length (funcall source-provider))))
                (setf live-entries (subseq entries 0 3)
                      now 160)
                (is (= 3 (length (funcall source-provider))))
                ;; A later twenty-second recovery is transient and must not
                ;; erase the already-running collapse interval.
                (setf live-entries entries
                      now 300)
                (is (= 8 (length (funcall source-provider))))
                (setf live-entries (subseq entries 0 3)
                      now 320)
                (is (= 3 (length (funcall source-provider))))
                ;; A collapsed source count alone cannot discard a root while
                ;; the surviving peers still deliver efficient responses.
                (setf now 449)
                (funcall
                 progress-callback
                 (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                  :processed-nodes 10000 :reused-nodes 9000
                  :fetched-nodes 1000 :request-count 10
                  :response-bytes 100000 :completed-p nil))
                (is (not (funcall yield-p)))
                (setf now 450)
                (funcall
                 progress-callback
                 (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                 :processed-nodes 12048 :reused-nodes 11048
                  :fetched-nodes 1000 :request-count 11
                  :response-bytes 101000 :completed-p nil))
                (is (not (funcall yield-p)))
                ;; After a full request window delivers no additional nodes,
                ;; high local throughput still retains the exact frontier.
                (setf now 749)
                (funcall
                 progress-callback
                 (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                  :processed-nodes 160000 :reused-nodes 159000
                  :fetched-nodes 1000 :request-count 75
                  :response-bytes 101000 :completed-p nil))
                (is (not (funcall yield-p)))
                ;; Only a following five-minute window with low aggregate
                ;; work corroborates the collapsed serving edge. The final
                ;; local batch keeps progress liveness fresh, excluding the
                ;; independent progress-stalled reason.
                (setf now 1049)
                (funcall
                 progress-callback
                 (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                  :processed-nodes 162048 :reused-nodes 161048
                  :fetched-nodes 1000 :request-count 139
                  :response-bytes 101000 :completed-p nil))
                (is (funcall yield-p))
                (error 'ethereum-lisp.snap-sync:snap-sync-heal-yielded))))
      (cons 'ethereum-lisp.cli::devnet-peer-manager-log
            (lambda (seen-node name &rest fields)
              (is (eq node seen-node))
              (push (cons name fields) logs))))
     (lambda ()
       (signals ethereum-lisp.snap-sync:snap-sync-heal-yielded
         (ethereum-lisp.cli::devnet-node-snap-import-with-failover
          node database pivot-header target-hash :target-number 64))))
    (let ((record
            (find "peer.snap.target_stale" logs
                  :key #'first :test #'string=)))
      (is record)
      (flet ((field (name)
               (loop for (key value) on (cdr record) by #'cddr
                     when (string= key name) return value)))
        (is (= 64 (field "target")))
        (is (= 205 (field "successor")))
        (is (string= "source-throughput-low" (field "reason")))))))

(deftest devnet-snap-collapsed-source-pool-yields-after-low-total-throughput
  (:layer :unit :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (database (make-memory-key-value-database))
         (pivot-header
           (block-header (ethereum-lisp.cli::devnet-node-genesis-block node)))
         (target-hash
           (make-hash32 (make-byte-vector 32 :initial-element 97)))
         (successor-hash
           (make-hash32 (make-byte-vector 32 :initial-element 98)))
         (entries
           (loop for index below 8
                 collect
                 (ethereum-lisp.cli::make-devnet-peer-entry
                  :id-hex (format nil "peer-~D" index))))
         (sources
           (loop repeat 8
                 collect
                 (ethereum-lisp.snap-sync:make-snap-sync-source
                  :account-range (lambda (request) (declare (ignore request)))
                  :storage-ranges (lambda (request) (declare (ignore request)))
                  :bytecodes (lambda (request) (declare (ignore request)))
                  :trie-nodes (lambda (request) (declare (ignore request))))))
         (entry-sources (mapcar #'cons entries sources))
         (live-entries (copy-list entries))
         (now 100)
         (logs '()))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::unix-time (lambda () now))
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (copy-list live-entries)))
      (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
            (lambda (entry)
              (or (cdr (assoc entry entry-sources :test #'eq))
                  (error "Missing test source"))))
      (cons 'ethereum-lisp.cli::devnet-node-stale-snap-successor
            (lambda (seen-node seen-target seen-number)
              (is (eq node seen-node))
              (is (hash32= target-hash seen-target))
              (is (= 0 seen-number))
              (values successor-hash 245)))
      (cons 'ethereum-lisp.snap-sync:snap-sync-import-state-multi
            (lambda (seen-database initial-sources &rest arguments)
              (is (eq database seen-database))
              (is (= 8 (length initial-sources)))
              (let ((source-provider (getf arguments :heal-source-provider))
                    (yield-p (getf arguments :heal-yield-p))
                    (progress-callback (getf arguments :on-heal-progress)))
                (is (functionp source-provider))
                (is (functionp yield-p))
                (is (functionp progress-callback))
                (setf live-entries (subseq entries 0 3)
                      now 110)
                (is (= 3 (length (funcall source-provider))))
                (funcall
                 progress-callback
                 (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                  :processed-nodes 1024 :reused-nodes 0
                  :fetched-nodes 1024 :request-count 64
                  :response-bytes 262144 :completed-p nil))
                ;; This full request window returns 48 nodes per request, well
                ;; above the per-response floor, and refreshes ordinary
                ;; productive progress at the exact five-minute boundary.
                ;; Aggregate work is nevertheless too small for the collapsed
                ;; pool to finish before public peers move their state window.
                (setf now 410)
                (funcall
                 progress-callback
                 (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                  :processed-nodes 30000 :reused-nodes 25904
                  :fetched-nodes 4096 :request-count 128
                  :response-bytes 524288 :completed-p nil))
                (is (funcall yield-p))
                (error 'ethereum-lisp.snap-sync:snap-sync-heal-yielded))))
      (cons 'ethereum-lisp.cli::devnet-peer-manager-log
            (lambda (seen-node name &rest fields)
              (is (eq node seen-node))
              (push (cons name fields) logs))))
     (lambda ()
       (signals ethereum-lisp.snap-sync:snap-sync-heal-yielded
         (ethereum-lisp.cli::devnet-node-snap-import-with-failover
          node database pivot-header target-hash :target-number 64))))
    (let ((record
            (find "peer.snap.target_stale" logs
                  :key #'first :test #'string=)))
      (is record)
      (flet ((field (name)
               (loop for (key value) on (cdr record) by #'cddr
                     when (string= key name) return value)))
        (is (= 64 (field "target")))
        (is (= 245 (field "successor")))
        (is (string= "source-throughput-low" (field "reason")))))))

(deftest devnet-snap-exhausted-source-generation-yields-to-a-stale-consensus-target
  (:layer :unit :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (database (make-memory-key-value-database))
         (pivot-header (block-header
                        (ethereum-lisp.cli::devnet-node-genesis-block node)))
         (target-hash
           (make-hash32 (make-byte-vector 32 :initial-element 95)))
         (successor-hash
           (make-hash32 (make-byte-vector 32 :initial-element 96)))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes (lambda (request) (declare (ignore request)))))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry :id-hex "peer-1"))
         (stale-successor-p nil)
         (attempts 0)
         (logs '()))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (list entry)))
      (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
            (lambda (seen-entry)
              (is (eq entry seen-entry))
              source))
      (cons 'ethereum-lisp.cli::devnet-node-stale-snap-successor
            (lambda (seen-node seen-target seen-number)
              (is (eq node seen-node))
              (is (hash32= target-hash seen-target))
              (is (= 0 seen-number))
              (if stale-successor-p
                  (values successor-hash 225)
                  (values nil nil))))
      (cons 'ethereum-lisp.snap-sync:snap-sync-import-state-multi
            (lambda (seen-database sources &rest arguments)
              (declare (ignore arguments))
              (is (eq database seen-database))
              (is (= 1 (length sources)))
              (incf attempts)
              (ethereum-lisp.snap-sync:snap-sync-state-unavailable
               "bytecodes")))
      (cons 'ethereum-lisp.cli::devnet-peer-manager-log
            (lambda (seen-node name &rest fields)
              (is (eq node seen-node))
              (push (cons name fields) logs))))
     (lambda ()
       ;; Finite source exhaustion inside the retention window preserves the
       ;; exact pivot and lets the ordinary coordinator wait for a new source.
       (signals ethereum-lisp.snap-sync:snap-sync-state-unavailable
         (ethereum-lisp.cli::devnet-node-snap-import-with-failover
          node database pivot-header target-hash :target-number 64))
       ;; The same explicit exhaustion must yield once a newer CL-authorized
       ;; target lies beyond the pinned geth stale-pivot window.
       (setf stale-successor-p t)
       (signals ethereum-lisp.snap-sync:snap-sync-heal-yielded
         (ethereum-lisp.cli::devnet-node-snap-import-with-failover
          node database pivot-header target-hash :target-number 64))))
    (is (= 2 attempts))
    (let ((record
            (find "peer.snap.target_stale" logs
                  :key #'first :test #'string=)))
      (is record)
      (flet ((field (name)
               (loop for (key value) on (cdr record) by #'cddr
                     when (string= key name) return value)))
        (is (= 64 (field "target")))
        (is (= 225 (field "successor")))
        (is (string= "sources-unavailable" (field "reason")))
        (is (string= (hash32-to-hex target-hash) (field "targetHash")))
        (is (string= (hash32-to-hex successor-hash)
                     (field "successorHash")))))))

(deftest devnet-snap-recent-efficient-heal-retains-exhausted-source-generation
  (:layer :unit :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (database (make-memory-key-value-database))
         (pivot-header (block-header
                        (ethereum-lisp.cli::devnet-node-genesis-block node)))
         (target-hash
           (make-hash32 (make-byte-vector 32 :initial-element 97)))
         (successor-hash
           (make-hash32 (make-byte-vector 32 :initial-element 98)))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes (lambda (request) (declare (ignore request)))))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry :id-hex "peer-1"))
         (now 100)
         (attempts 0)
         (logs '()))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::unix-time (lambda () now))
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (list entry)))
      (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
            (lambda (seen-entry)
              (is (eq entry seen-entry))
              source))
      (cons 'ethereum-lisp.cli::devnet-node-stale-snap-successor
            (lambda (seen-node seen-target seen-number)
              (is (eq node seen-node))
              (is (hash32= target-hash seen-target))
              (is (= 0 seen-number))
              (values successor-hash 225)))
      (cons 'ethereum-lisp.snap-sync:snap-sync-import-state-multi
            (lambda (seen-database sources &rest arguments)
              (is (eq database seen-database))
              (is (= 1 (length sources)))
              (incf attempts)
              (let ((progress-callback (getf arguments :on-heal-progress)))
                (is (functionp progress-callback))
                (case attempts
                  (1
                   (funcall
                    progress-callback
                    (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                     :processed-nodes 0 :reused-nodes 0 :fetched-nodes 0
                     :request-count 0 :response-bytes 0 :completed-p nil))
                   (setf now 110)
                   (funcall
                    progress-callback
                    (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                     :processed-nodes 1024 :reused-nodes 0
                     :fetched-nodes 1024 :request-count 64
                     :response-bytes 262144 :completed-p nil))
                   (setf now 111))
                  (2 (setf now 409))
                  (3 (setf now 410))))
              (ethereum-lisp.snap-sync:snap-sync-state-unavailable
               "trie-nodes")))
      (cons 'ethereum-lisp.cli::devnet-peer-manager-log
            (lambda (seen-node name &rest fields)
              (is (eq node seen-node))
              (push (cons name fields) logs))))
     (lambda ()
       ;; A generation which just returned a full useful response window is
       ;; retained across more than one finite coordinator attempt.
       (signals ethereum-lisp.snap-sync:snap-sync-state-unavailable
         (ethereum-lisp.cli::devnet-node-snap-import-with-failover
          node database pivot-header target-hash :target-number 64))
       (signals ethereum-lisp.snap-sync:snap-sync-state-unavailable
         (ethereum-lisp.cli::devnet-node-snap-import-with-failover
          node database pivot-header target-hash :target-number 64))
       ;; The exact five-minute boundary restores the stale-target escape.
       (signals ethereum-lisp.snap-sync:snap-sync-heal-yielded
         (ethereum-lisp.cli::devnet-node-snap-import-with-failover
          node database pivot-header target-hash :target-number 64))))
    (is (= 3 attempts))
    (is (= 1 (count "peer.snap.target_stale" logs
                    :key #'first :test #'string=)))))

(deftest devnet-snap-underfilled-heal-waits-for-low-total-throughput
  (:layer :unit :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (database (make-memory-key-value-database))
         (pivot-header (block-header
                        (ethereum-lisp.cli::devnet-node-genesis-block node)))
         (target-hash
           (make-hash32 (make-byte-vector 32 :initial-element 93)))
         (successor-hash
           (make-hash32 (make-byte-vector 32 :initial-element 94)))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) (declare (ignore request)))
            :storage-ranges (lambda (request) (declare (ignore request)))
            :bytecodes (lambda (request) (declare (ignore request)))
            :trie-nodes (lambda (request) (declare (ignore request)))))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry :id-hex "peer-1"))
         (now 100)
         (logs '()))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::unix-time (lambda () now))
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (list entry)))
      (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
            (lambda (seen-entry)
              (is (eq entry seen-entry))
              source))
      (cons 'ethereum-lisp.cli::devnet-node-stale-snap-successor
            (lambda (seen-node seen-target seen-number)
              (is (eq node seen-node))
              (is (hash32= target-hash seen-target))
              (is (= 0 seen-number))
              (values successor-hash 225)))
      (cons 'ethereum-lisp.snap-sync:snap-sync-import-state-multi
            (lambda (seen-database sources &rest arguments)
              (is (eq database seen-database))
              (is (= 1 (length sources)))
              (let ((yield-p (getf arguments :heal-yield-p))
                    (progress-callback (getf arguments :on-heal-progress)))
                (is (functionp yield-p))
                (is (functionp progress-callback))
                ;; Establish a healthy 64-request window at sixteen fetched
                ;; nodes per request.
                (setf now 110)
                (funcall
                 progress-callback
                 (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                  :processed-nodes 4096 :reused-nodes 3072
                  :fetched-nodes 1024 :request-count 64
                  :response-bytes 262144 :completed-p nil))
                ;; A second complete request window returns only one node per
                ;; request, but unlocks enough local work to exceed the
                ;; aggregate throughput floor.
                (setf now 409)
                (funcall
                 progress-callback
                 (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                  :processed-nodes 200000 :reused-nodes 198912
                  :fetched-nodes 1088 :request-count 128
                  :response-bytes 266240 :completed-p nil))
                (is (not (funcall yield-p)))
                ;; Close the first five-minute throughput window. Underfilled
                ;; responses alone must not discard this productive frontier.
                (setf now 410)
                (funcall
                 progress-callback
                 (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                  :processed-nodes 200000 :reused-nodes 198912
                  :fetched-nodes 1088 :request-count 128
                  :response-bytes 266240 :completed-p nil))
                (is (not (funcall yield-p)))
                ;; A following complete window with only sparse remote and
                ;; local progress now proves low total throughput. This keeps
                ;; progress liveness fresh while permitting a stale rebase.
                (setf now 710)
                (funcall
                 progress-callback
                 (ethereum-lisp.snap-sync::%make-snap-sync-heal-progress
                  :processed-nodes 202048 :reused-nodes 200896
                  :fetched-nodes 1152 :request-count 192
                  :response-bytes 270336 :completed-p nil))
                (is (funcall yield-p))
                (error 'ethereum-lisp.snap-sync:snap-sync-heal-yielded))))
      (cons 'ethereum-lisp.cli::devnet-peer-manager-log
            (lambda (seen-node name &rest fields)
              (is (eq node seen-node))
              (push (cons name fields) logs))))
     (lambda ()
       (signals ethereum-lisp.snap-sync:snap-sync-heal-yielded
         (ethereum-lisp.cli::devnet-node-snap-import-with-failover
          node database pivot-header target-hash :target-number 64))))
    (let ((record
            (find "peer.snap.target_stale" logs
                  :key #'first :test #'string=)))
      (is record)
      (flet ((field (name)
               (loop for (key value) on (cdr record) by #'cddr
                     when (string= key name) return value)))
        (is (= 64 (field "target")))
        (is (= 225 (field "successor")))
        (is (string= "response-throughput-low" (field "reason")))))))

(deftest devnet-snap-heal-yield-skips-the-forward-gap-fallback
  (:layer :unit :module :p2p)
  (let ((node
          (ethereum-lisp.cli:make-devnet-node
           :genesis-json *eth-sync-paris-genesis-json*
           :port 0 :public-port 0))
        (target (make-hash32 (make-byte-vector 32 :initial-element 83)))
        (attempts 0))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-snap-sync-pivot-attempt
            (lambda (seen-node seen-target)
              (is (eq node seen-node))
              (is (hash32= target seen-target))
              (incf attempts)
              (error 'ethereum-lisp.snap-sync:snap-sync-heal-yielded))))
     (lambda ()
       (is (eq :stale-target
               (ethereum-lisp.cli::devnet-node-snap-sync-target node target)))))
    (is (= 1 attempts))
    (is (ethereum-lisp.cli::devnet-node-snap-session-rebase-p node))))

(deftest devnet-snap-restart-pin-waits-for-a-peer-and-is-consumed-on-attempt
  (:layer :unit :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (target (make-hash32 (make-byte-vector 32 :initial-element 77)))
         (snap-entries nil)
         (gap-calls 0)
         (snap-calls 0))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-active-snap-target
            (lambda (seen-node latest-target)
              (is (eq node seen-node))
              (is (null latest-target))
              target))
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              snap-entries))
      (cons 'ethereum-lisp.cli::devnet-node-snap-sync-target
            (lambda (seen-node seen-target)
              (is (eq node seen-node))
              (is (hash32= target seen-target))
              (incf snap-calls)
              7))
      (cons 'ethereum-lisp.cli::devnet-node-fill-sync-gaps-with-live-peer
            (lambda (seen-node)
              (is (eq node seen-node))
              (incf gap-calls)
              3)))
     (lambda ()
       ;; Merely observing an old durable session before any Snap peer connects
       ;; cannot consume the one post-restart recovery attempt.
       (is (= 3 (ethereum-lisp.cli::devnet-node-multi-sync-pass node)))
       (is (ethereum-lisp.cli::devnet-node-snap-session-resume-p node))
       (is (= 1 gap-calls))
       (is (= 0 snap-calls))
       ;; Starting the actual attempt consumes the process-local exception. If
       ;; this source generation later exhausts, the next pass may rebase.
       (setf snap-entries (list :snap-peer))
       (is (= 7 (ethereum-lisp.cli::devnet-node-multi-sync-pass node)))
       (is (not
            (ethereum-lisp.cli::devnet-node-snap-session-resume-p node)))
       (is (= 1 gap-calls))
       (is (= 1 snap-calls))))))

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
                               callback-target
                               &key preferred-entry target-number)
                        (declare (ignore callback-node))
                        (is (eq :target-source preferred-entry))
                        (is (eq database callback-database))
                        (is (hash32= pivot-hash
                                     (block-header-hash pivot-header)))
                        (is (hash32= target-hash callback-target))
                        (is (= 164 target-number))
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
                   ;; This test invokes the lower-level target routine
                   ;; directly. Production consumes the one restart pin in
                   ;; DEVNET-NODE-MULTI-SYNC-PASS immediately before doing so.
                   (setf
                    (ethereum-lisp.cli::devnet-node-snap-session-resume-p node)
                    nil)
                   ;; Crossing the ordinary pivot-age window is not itself a
                   ;; reason to discard productive durable state work.
                   (ethereum-lisp.cli::call-with-devnet-node-store-guard
                    node
                    (lambda ()
                      (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
                       store stale-newer-target)))
                   (is (hash32=
                        target-hash
                        (ethereum-lisp.cli::devnet-node-active-snap-target
                         node stale-newer-target-hash)))
                   ;; Only the healer's bounded liveness decision authorizes
                   ;; the next pass to adopt the newer CL target.
                   (setf
                    (ethereum-lisp.cli::devnet-node-snap-session-rebase-p node)
                    t)
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
                   ;; FCU targets are process-local.  If Lighthouse has not
                   ;; replayed one after a restart, the surviving skeleton is
                   ;; still the only consensus-authorized target and must
                   ;; restart SNAP rather than leave the coordinator in gap
                   ;; filling forever.
                   (is (hash32=
                        target-hash
                        (ethereum-lisp.cli::devnet-node-active-snap-target
                         node nil)))
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
                           :number 285 :state-root new-root
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
                      (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
                       store (make-block :header new-target))))
                   ;; Even without a healer checkpoint, a matching durable
                   ;; range session overrides the ordinary pivot-relative
                   ;; staleness timer for one real recovery attempt. Releasing
                   ;; it before a peer is tried made every routine deploy
                   ;; change pivot and repeat the root scan.
                   (is (hash32=
                        (block-header-hash old-target)
                        (ethereum-lisp.cli::devnet-node-active-snap-target
                         node (block-header-hash new-target))))
                   ;; Consuming the restart attempt does not itself authorize
                   ;; a rebase: a productive healer may run for many slots.
                   (setf
                    (ethereum-lisp.cli::devnet-node-snap-session-resume-p
                     node)
                    nil)
                   (is (hash32=
                        (block-header-hash old-target)
                        (ethereum-lisp.cli::devnet-node-active-snap-target
                         node (block-header-hash new-target))))
                   ;; The healer's explicit stale-target decision releases the
                   ;; durable session for one atomic rebase.
                   (setf
                    (ethereum-lisp.cli::devnet-node-snap-session-rebase-p node)
                    t)
                   (is (hash32=
                        (block-header-hash new-target)
                        (ethereum-lisp.cli::devnet-node-active-snap-target
                         node (block-header-hash new-target))))
                   (ethereum-lisp.cli::call-with-devnet-node-store-guard
                    node
                    (lambda ()
                      (ethereum-lisp.cli::devnet-node-rebase-stale-snap-progress
                       node database new-target new-pivot)))
                   (is (not
                        (ethereum-lisp.cli::devnet-node-snap-session-rebase-p
                         node)))
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
                           restored)))
                     ;; Explicit authority-driven rebase still invalidates the
                     ;; old frontier atomically with the two progress records.
                     (is (not
                          (ethereum-lisp.snap-sync:snap-sync-heal-checkpoint-present-p
                           database restored))))
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

(deftest devnet-snap-target-resolution-uses-the-live-eth-pool
  (:layer :integration :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "eth-header-source" :peer :peer :request-queue :queue))
         (target-hash
           (make-hash32 (make-byte-vector 32 :initial-element 8)))
         (snap-only-observations '())
         (resolve-calls 0))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (callback-node &key snap-only-p)
              (declare (ignore callback-node))
              (push snap-only-p snap-only-observations)
              (list entry)))
      (cons 'ethereum-lisp.cli::devnet-peer-resolve-snap-target
            (lambda (callback-entry callback-target)
              (is (eq entry callback-entry))
              (is (hash32= target-hash callback-target))
              (incf resolve-calls)
              (values :target-header :pivot-header '(:tail-header)))))
     (lambda ()
       (multiple-value-bind (resolved target pivot tail)
           (ethereum-lisp.cli::devnet-node-resolve-snap-target
            node target-hash)
         (is (eq entry resolved))
         (is (eq :target-header target))
         (is (eq :pivot-header pivot))
         (is (equal '(:tail-header) tail)))))
    ;; Positive witnesses: one real resolver pass reached the injected ETH
    ;; source, and the production live-entry query did not ask for SNAP-only.
    (is (= 1 resolve-calls))
    (is (equal '(nil) snap-only-observations))))

(deftest devnet-snap-pivot-does-not-fall-forward-to-an-unstable-root
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
       (signals ethereum-lisp.eth-sync:eth-sync-multi-peer-error
         (ethereum-lisp.cli::devnet-node-select-snap-pivot
          node entry (list old parent target)))
       ;; A finite coordinator retry of the same pivot must not send the same
       ;; unavailable peer another probe one second later.
       (signals ethereum-lisp.eth-sync:eth-sync-multi-peer-error
         (ethereum-lisp.cli::devnet-node-select-snap-pivot
          node entry (list old parent target)))
       ;; A genuinely different pivot clears only the process-local rejection
       ;; set and gives the same peer a fresh, successful opportunity.
       (multiple-value-bind (selected-entry selected-header selected-tail)
           (ethereum-lisp.cli::devnet-node-select-snap-pivot
            node entry (list parent target))
         (is (eq entry selected-entry))
         (is (eq parent selected-header))
         (is (equal (list parent target) selected-tail)))))
    (is (= 2 (length probes)))
    (is (some (lambda (root) (hash32= old-root root)) probes))
    (is (some (lambda (root) (hash32= parent-root root)) probes))
    (is (= 1 (length logs)))
    (is (string= "peer.snap.pivot_unavailable" (caar logs)))
    (is (= 0 (ethereum-lisp.cli::devnet-peer-score
              (ethereum-lisp.cli::devnet-node-peer-table node) peer-id)))))

(deftest devnet-snap-exhausted-selection-retains-recent-efficient-pivot
  (:layer :integration :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "recent-efficient-peer"))
         (pivot
           (make-block-header
            :number 100 :gas-limit 30000000
            :state-root
            (make-hash32 (make-byte-vector 32 :initial-element 31))))
         (target
           (make-block-header
            :number 164 :gas-limit 30000000
            :state-root
            (make-hash32 (make-byte-vector 32 :initial-element 32))))
         (pivot-hash (block-header-hash pivot))
         (target-hash (block-header-hash target))
         (successor-hash
           (make-hash32 (make-byte-vector 32 :initial-element 33)))
         (now 110)
         (logs '()))
    (ethereum-lisp.cli::devnet-node-note-snap-pivot-unavailable
     node pivot-hash entry)
    (ethereum-lisp.cli::devnet-node-note-snap-pivot-efficient-response
     node pivot-hash now)
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::unix-time (lambda () now))
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (list entry)))
      (cons 'ethereum-lisp.cli::devnet-node-stale-snap-successor
            (lambda (seen-node seen-target seen-number)
              (is (eq node seen-node))
              (is (hash32= target-hash seen-target))
              (is (= 100 seen-number))
              (values successor-hash 225)))
      (cons 'ethereum-lisp.cli::devnet-peer-manager-log
            (lambda (seen-node name &rest fields)
              (is (eq node seen-node))
              (push (cons name fields) logs))))
     (lambda ()
       ;; The rejection set filters the whole old generation, but recent
       ;; serving evidence still pins the exact root on the next pass.
       (setf now 409)
       (signals ethereum-lisp.eth-sync:eth-sync-multi-peer-error
         (ethereum-lisp.cli::devnet-node-select-snap-pivot
          node entry (list pivot target)))
       ;; Selection itself performs the eventual escape: no importer remains
       ;; available to raise another aggregate state-unavailable condition.
       (setf now 410)
       (signals ethereum-lisp.snap-sync:snap-sync-heal-yielded
         (ethereum-lisp.cli::devnet-node-select-snap-pivot
          node entry (list pivot target)))))
    (let ((record
            (find "peer.snap.target_stale" logs
                  :key #'first :test #'string=)))
      (is record)
      (flet ((field (name)
               (loop for (key value) on (cdr record) by #'cddr
                     when (string= key name) return value)))
        (is (= 164 (field "target")))
        (is (= 225 (field "successor")))
        (is (string= "sources-unavailable" (field "reason")))))))

(deftest devnet-snap-full-import-pruning-waits-for-a-new-source
  (:layer :integration :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (target (make-hash32 (make-byte-vector 32 :initial-element 91)))
         (attempts '())
         (logs '()))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons
       'ethereum-lisp.cli::devnet-node-snap-sync-pivot-attempt
       (lambda (seen-node seen-target)
         (is (eq node seen-node))
         (is (hash32= target seen-target))
         (push :conventional attempts)
         (ethereum-lisp.snap-sync:snap-sync-state-unavailable
          "storage-range")))
      (cons
       'ethereum-lisp.cli::devnet-peer-manager-log
       (lambda (seen-node name &rest fields)
         (is (eq node seen-node))
         (push (cons name fields) logs))))
     (lambda ()
       (is (eq :waiting-for-source
               (ethereum-lisp.cli::devnet-node-snap-sync-target node target)))
       (is (equal '(:conventional) (nreverse attempts)))
       (is (= 1 (count "peer.snap.pivot_wait" logs
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
            (list "devnet" "--hoodi" "--nodiscover=false" "--no-serve")))
         (dns-disabled
           (ethereum-lisp.cli::devnet-cli-options
            (list "devnet" "--hoodi" "--discovery.dns" "" "--no-serve"))))
    (is (= 3 (length (getf defaults :bootnodes))))
    (is (string= "enrtree://AKA3AM6LPBYEUDMVNU3BSVQJ5AD45Y7YPOHJLEF6W26QOE4VTUDPE@all.hoodi.ethdisco.net"
                 (getf defaults :discovery-dns)))
    (is (= 30303 (getf defaults :p2p-port)))
    (is (getf defaults :discovery-enabled-p))
    ;; Explicit empty bootnodes override the public preset rather than being
    ;; mistaken for an absent option and silently refilled.
    (is (null (getf disabled :bootnodes)))
    (is (not (getf disabled :discovery-enabled-p)))
    (is (getf reenabled :discovery-enabled-p))
    (is (null (getf dns-disabled :discovery-dns)))))

(deftest devnet-discovery-has-a-genesis-fork-filter-while-store-is-busy
  (:layer :unit :module :p2p)
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (genesis (ethereum-lisp.cli::devnet-node-genesis-block node))
         (timestamp (block-header-timestamp (block-header genesis)))
         (expected
           (make-eth-chain-context
            (ethereum-lisp.cli::devnet-node-config node)
            (hash32-bytes (block-hash genesis)) 0 timestamp timestamp)))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::call-with-devnet-node-store-guard-if-free
            (lambda (seen-node thunk)
              (declare (ignore thunk))
              (is (eq node seen-node))
              (values nil nil))))
     (lambda ()
       (let ((context (ethereum-lisp.cli::devnet-node-chain-context node)))
         (is context)
         (is (eq context
                 (ethereum-lisp.cli::devnet-node-chain-context-cache node)))
         (is
          (equalp (eth-chain-context-record-pairs expected)
                  (eth-chain-context-record-pairs context)))
         ;; A fresh SNAP import can hold the store guard before discovery's
         ;; first pass, but the shared DHT must still be chain filtered.
         (is (functionp
              (ethereum-lisp.cli::devnet-discovery-record-filter node))))))))

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

(deftest devnet-datadir-persists-eip1459-anti-rollback-sequence-by-authority
  (:layer :unit :module :cli)
  (let* ((datadir (devnet-cli-temp-directory "ethereum-lisp-dns-sequence"))
         (path (ethereum-lisp.cli::devnet-cli-datadir-dns-seq-path datadir))
         (url (getf (eip1459-test-fixture) :url)))
    (unwind-protect
         (progn
           (is (null (ethereum-lisp.cli::devnet-cli-load-dns-sequence
                      path url)))
           (is (= 2195
                  (ethereum-lisp.cli::devnet-cli-write-dns-sequence
                   path url 2195)))
           (is (= 2195
                  (ethereum-lisp.cli::devnet-cli-load-dns-sequence path url)))
           ;; A configured authority change gets no floor from the old tree.
           (is (null
                (ethereum-lisp.cli::devnet-cli-load-dns-sequence
                 path (concatenate 'string url ".changed"))))
           (devnet-cli-write-temp-file path "malformed")
           (is (eip1459-test-errors-p
                (lambda ()
                  (ethereum-lisp.cli::devnet-cli-load-dns-sequence
                   path url)))))
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
        (ethereum-lisp.cli::devnet-peer-request-queue-close queue)))
    (let* ((queue (ethereum-lisp.cli::make-devnet-peer-request-queue))
           (submitted-condition nil)
           (submitter
             (sb-thread:make-thread
              (lambda ()
                (handler-case
                    (ethereum-lisp.cli::devnet-peer-request-queue-submit-job
                     queue
                     (ethereum-lisp.cli::make-devnet-peer-request-job
                      (lambda () nil)
                      :snap-response-id
                      ethereum-lisp.snap:+snap-message-account-range+
                      :snap-request-id 404))
                  (serious-condition (condition)
                    (setf submitted-condition condition))))
              :name "section5-active-snap-close")))
      (unwind-protect
           (progn
             (wait-for-test-condition
              "queued active snap request" 2d0 (lambda () (queued-p queue)))
             (funcall
              (funcall
               (ethereum-lisp.cli::devnet-peer-pending-request queue)))
             (ethereum-lisp.cli::devnet-peer-request-queue-close queue)
             (is (not (eq :timeout
                          (sb-thread:join-thread
                           submitter :timeout 2 :default :timeout))))
             (is (typep submitted-condition 'serious-condition)))
        (ethereum-lisp.cli::devnet-peer-request-queue-close queue))))
  #-sbcl
  (is t))

(deftest devnet-snap-wire-request-ids-are-unique-and-logical-ids-survive
  (:layer :unit :module :p2p)
  #+sbcl
  (let ((queue (ethereum-lisp.cli::make-devnet-peer-request-queue)))
    (unwind-protect
         (let* ((logical
                  (ethereum-lisp.snap:make-snap-get-account-range
                   7 (make-byte-vector 32) (make-byte-vector 32)
                   (make-byte-vector 32) 1024))
                (first-id
                  (ethereum-lisp.cli::devnet-peer-request-queue-allocate-snap-id
                   queue))
                (second-id
                  (ethereum-lisp.cli::devnet-peer-request-queue-allocate-snap-id
                   queue))
                (wire
                  (ethereum-lisp.cli::devnet-snap-request-with-id
                   ethereum-lisp.snap:+snap-message-get-account-range+
                   logical second-id))
                (response
                  (ethereum-lisp.snap:make-snap-account-range
                   second-id '() '()))
                (restored
                  (ethereum-lisp.cli::devnet-snap-response-with-id
                   ethereum-lisp.snap:+snap-message-account-range+
                   response 7)))
           (is (plusp first-id))
           (is (< first-id second-id))
           (is (= 7 (ethereum-lisp.snap:snap-get-account-range-id logical)))
           (is (= second-id
                  (ethereum-lisp.snap:snap-get-account-range-id wire)))
           (is (= second-id
                  (ethereum-lisp.snap:snap-account-range-id response)))
           (is (= 7 (ethereum-lisp.snap:snap-account-range-id restored))))
      (ethereum-lisp.cli::devnet-peer-request-queue-close queue)))
  #-sbcl
  (is t))

(deftest devnet-snap-timeout-reverts-only-the-request-and-absorbs-late-response
  (:layer :integration :module :p2p)
  #+sbcl
  (let* ((queue (ethereum-lisp.cli::make-devnet-peer-request-queue))
         (now (ethereum-lisp.cli::devnet-peer-request-monotonic-seconds))
         (expired
           (ethereum-lisp.cli::make-devnet-peer-request-job
            (lambda () nil)
            :snap-response-id
            ethereum-lisp.snap:+snap-message-account-range+
            :snap-request-id 101
            :snap-logical-request-id 1))
         (replacement
           (ethereum-lisp.cli::make-devnet-peer-request-job
            (lambda () nil)
            :snap-response-id
            ethereum-lisp.snap:+snap-message-account-range+
            :snap-request-id 102
            :snap-logical-request-id 1)))
    (unwind-protect
         (progn
           (setf
            (ethereum-lisp.cli::devnet-peer-request-job-started-at expired)
            (- now 7d0)
            (ethereum-lisp.cli::devnet-peer-request-job-timeout-seconds expired)
            6d0
            (ethereum-lisp.cli::devnet-peer-request-job-deadline expired)
            (- now 1d0)
            (ethereum-lisp.cli::devnet-peer-request-queue-active queue)
            (list expired)
            (ethereum-lisp.cli::devnet-peer-request-queue-pending queue)
            (list replacement))
           (is (eq replacement
                   (ethereum-lisp.cli::devnet-peer-request-queue-take-eligible
                    queue)))
           (is (ethereum-lisp.cli::devnet-peer-request-job-done-p expired))
           (is (typep
                (ethereum-lisp.cli::devnet-peer-request-job-condition expired)
                'ethereum-lisp.snap-sync:snap-sync-request-timeout))
           (is (not
                (ethereum-lisp.cli::devnet-peer-request-queue-closed-p queue)))
           (let ((handler
                   (ethereum-lisp.cli::devnet-peer-snap-response-handler
                    queue)))
             ;; The expired wire response is valid but stale. It must not
             ;; complete the replacement or tear down the peer session.
             (is (funcall
                  handler ethereum-lisp.snap:+snap-message-account-range+
                  (ethereum-lisp.snap:encode-snap-message
                   ethereum-lisp.snap:+snap-message-account-range+
                   (ethereum-lisp.snap:make-snap-account-range 101 '() '()))))
             (is (not
                  (ethereum-lisp.cli::devnet-peer-request-job-done-p
                   replacement)))
             (is (funcall
                  handler ethereum-lisp.snap:+snap-message-account-range+
                  (ethereum-lisp.snap:encode-snap-message
                   ethereum-lisp.snap:+snap-message-account-range+
                   (ethereum-lisp.snap:make-snap-account-range 102 '() '()))))
             (is (ethereum-lisp.cli::devnet-peer-request-job-done-p
                  replacement))
             (is (= 1
                    (ethereum-lisp.snap:snap-account-range-id
                     (first
                      (ethereum-lisp.cli::devnet-peer-request-job-values
                       replacement)))))))
      (ethereum-lisp.cli::devnet-peer-request-queue-close queue)))
  #-sbcl
  (is t))

(deftest devnet-peer-request-queue-pipelines-distinct-snap-response-types
  (:layer :integration :module :p2p)
  #+sbcl
  (labels
      ((queue-count (queue accessor)
         (sb-thread:with-mutex
             ((ethereum-lisp.cli::devnet-peer-request-queue-lock queue))
           (length (funcall accessor queue))))
       (wait-count (queue accessor count description)
         (wait-for-test-condition
          description 2d0
          (lambda () (= count (queue-count queue accessor))))))
    (let* ((queue (ethereum-lisp.cli::make-devnet-peer-request-queue))
           (pending
             (ethereum-lisp.cli::devnet-peer-pending-request queue))
           (handler
             (ethereum-lisp.cli::devnet-peer-snap-response-handler queue))
           (started '())
           (account-one nil)
           (storage nil)
           (account-two nil)
           (threads '()))
      (labels
          ((submit (response-id request-id marker result-setter)
             (let ((thread
                     (sb-thread:make-thread
                      (lambda ()
                        (funcall
                         result-setter
                         (ethereum-lisp.cli::devnet-peer-request-queue-submit-job
                          queue
                          (ethereum-lisp.cli::make-devnet-peer-request-job
                           (lambda () (push marker started))
                           :snap-response-id response-id
                           :snap-request-id request-id))))
                      :name "section5-pipelined-snap-submit")))
               (push thread threads))))
        (unwind-protect
             (progn
               ;; Preserve queue order deterministically: the second account
               ;; job must sit ahead of storage, yet storage must bypass it
               ;; while the first account response type is occupied.
               (submit ethereum-lisp.snap:+snap-message-account-range+ 101
                       :account-one (lambda (value) (setf account-one value)))
               (wait-count
                queue #'ethereum-lisp.cli::devnet-peer-request-queue-pending
                1 "first pipelined snap request")
               (submit ethereum-lisp.snap:+snap-message-account-range+ 202
                       :account-two (lambda (value) (setf account-two value)))
               (wait-count
                queue #'ethereum-lisp.cli::devnet-peer-request-queue-pending
                2 "second pipelined snap request")
               (submit ethereum-lisp.snap:+snap-message-storage-ranges+ 303
                       :storage (lambda (value) (setf storage value)))
               (wait-count
                queue #'ethereum-lisp.cli::devnet-peer-request-queue-pending
                3 "third pipelined snap request")
               (funcall (funcall pending))
               (funcall (funcall pending))
               (is (equal '(:account-one :storage) (reverse started)))
               (is (null (funcall pending)))
               (is (= 2
                      (queue-count
                       queue #'ethereum-lisp.cli::devnet-peer-request-queue-active)))
               (is
                (funcall
                 handler ethereum-lisp.snap:+snap-message-storage-ranges+
                 (ethereum-lisp.snap:encode-snap-message
                  ethereum-lisp.snap:+snap-message-storage-ranges+
                  (ethereum-lisp.snap:make-snap-storage-ranges 303 nil nil))))
               (signals error
                 (funcall
                  handler ethereum-lisp.snap:+snap-message-account-range+
                  (ethereum-lisp.snap:encode-snap-message
                   ethereum-lisp.snap:+snap-message-account-range+
                   (ethereum-lisp.snap:make-snap-account-range 999 nil nil))))
               (is
                (funcall
                 handler ethereum-lisp.snap:+snap-message-account-range+
                 (ethereum-lisp.snap:encode-snap-message
                  ethereum-lisp.snap:+snap-message-account-range+
                  (ethereum-lisp.snap:make-snap-account-range 101 nil nil))))
               (funcall (funcall pending))
               (is (equal '(:account-one :storage :account-two)
                          (reverse started)))
               (is
                (funcall
                 handler ethereum-lisp.snap:+snap-message-account-range+
                 (ethereum-lisp.snap:encode-snap-message
                  ethereum-lisp.snap:+snap-message-account-range+
                  (ethereum-lisp.snap:make-snap-account-range 202 nil nil))))
               (dolist (thread threads)
                 (is (not (eq :timeout
                              (sb-thread:join-thread
                               thread :timeout 2 :default :timeout)))))
               (is (= 101
                      (ethereum-lisp.snap:snap-account-range-id account-one)))
               (is (= 303
                      (ethereum-lisp.snap:snap-storage-ranges-id storage)))
               (is (= 202
                      (ethereum-lisp.snap:snap-account-range-id account-two)))
               (is (zerop
                    (queue-count
                     queue #'ethereum-lisp.cli::devnet-peer-request-queue-active))))
          (ethereum-lisp.cli::devnet-peer-request-queue-close queue)
          (dolist (thread threads)
            (when (sb-thread:thread-alive-p thread)
              (sb-thread:join-thread thread :timeout 2 :default nil)))))))
  #-sbcl
  (is t))

(deftest devnet-queued-snap-source-exposes-live-trienode-capacity
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((qos (ethereum-lisp.cli::make-devnet-snap-qos))
         (queue (ethereum-lisp.cli::make-devnet-peer-request-queue qos))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "trienode-capacity-peer"
            :request-queue queue))
         (node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (pool (ethereum-lisp.cli::make-devnet-snap-source-pool node))
         (source
           (ethereum-lisp.cli::devnet-peer-queued-snap-source entry))
         (pooled-source
           (ethereum-lisp.cli::devnet-snap-source-pool-source pool entry))
         (capacity
           (ethereum-lisp.snap-sync:snap-sync-source-trie-node-capacity
            source))
         (pooled-capacity
           (ethereum-lisp.snap-sync:snap-sync-source-trie-node-capacity
            pooled-source)))
    (is (functionp capacity))
    (is (functionp pooled-capacity))
    (is (= 1 (funcall capacity)))
    (is (= 1 (funcall pooled-capacity)))
    ;; TrieNodes is measured in returned-node units. A fast 1,024-node reply
    ;; takes the shared rate tracker to the protocol ceiling, and the source
    ;; exposes that live value rather than a second healer-local estimate.
    (is (= 1024
           (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
            queue ethereum-lisp.snap:+snap-message-trie-nodes+
            1024 1d0)))
    (is (= 1024 (funcall capacity)))
    ;; The account-pinned pool wrapper must retain the fixed transport's live
    ;; capacity callback for the separate cross-source TrieNodes scheduler.
    (is (= 1024 (funcall pooled-capacity))))
  #-sbcl
  (is t))

(deftest devnet-snap-request-capacity-follows-geth-throughput-ewma
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((queue (ethereum-lisp.cli::make-devnet-peer-request-queue))
         (response-id ethereum-lisp.snap:+snap-message-account-range+)
         (minimum ethereum-lisp.cli::+devnet-snap-min-request-bytes+)
         (maximum ethereum-lisp.cli::+devnet-snap-max-request-bytes+))
    (is (= minimum
           (ethereum-lisp.cli::devnet-peer-request-queue-snap-capacity
            queue response-id)))
    ;; Geth starts a first peer at zero throughput, applies the 0.1 EWMA, then
    ;; derives the request from throughput * timeout. A sufficiently fast first
    ;; 64 KiB response therefore reaches the protocol cap immediately; the old
    ;; local double-step limiter would return only 128 KiB here.
    (is (= maximum
           (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
            queue response-id minimum 0.05d0)))
    ;; Geth interprets a zero delivery as no usable throughput, but does not
    ;; contaminate the peer's shared RTT with the timeout/unavailable interval.
    (is (= minimum
           (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
            queue response-id 0 30d0)))
    (multiple-value-bind (capacity rtt samples)
        (ethereum-lisp.cli::devnet-peer-request-queue-snap-statistics
         queue response-id)
      (is (= minimum capacity))
      ;; The tracker RTT is shared by all response types and starts at 20s:
      ;; 0.9 * 20 + 0.1 * 0.05 = 18.005. The zero delivery leaves it intact.
      (is (< (abs (- 18.005d0 rtt)) 1d-12))
      (is (= 2 samples)))
    ;; RTT belongs to Geth's peer tracker, not to one message kind. A newly
    ;; observed ByteCodes rate sees the AccountRange measurement immediately.
    (multiple-value-bind (capacity rtt samples)
        (ethereum-lisp.cli::devnet-peer-request-queue-snap-statistics
         queue ethereum-lisp.snap:+snap-message-bytecodes+)
      (is (= 1 capacity))
      (is (< (abs (- 18.005d0 rtt)) 1d-12))
      (is (zerop samples)))
    (is (= 2
           (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
            queue ethereum-lisp.snap:+snap-message-bytecodes+ 1 10d0)))
    (multiple-value-bind (capacity rtt samples)
        (ethereum-lisp.cli::devnet-peer-request-queue-snap-statistics
         queue response-id)
      (is (= minimum capacity))
      (is (< (abs (- 17.2045d0 rtt)) 1d-12))
      (is (= 2 samples)))
    (is (= maximum
           (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
            queue response-id minimum 0.05d0)))
    ;; Repeated slow measurements reduce capacity but never below 64 KiB.
    (loop repeat 64
          do (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
              queue response-id minimum 30d0))
    (is (= minimum
           (ethereum-lisp.cli::devnet-peer-request-queue-snap-capacity
            queue response-id)))
    (multiple-value-bind (capacity rtt samples)
        (ethereum-lisp.cli::devnet-peer-request-queue-snap-statistics
         queue response-id)
      (is (= minimum capacity))
      (is (plusp rtt))
      (is (= 67 samples))))
  #-sbcl
  (is t))

(deftest devnet-snap-request-timeout-follows-live-pool-rtt
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((qos (ethereum-lisp.cli::make-devnet-snap-qos))
         (queues
           (loop repeat 16
                 collect
                 (ethereum-lisp.cli::make-devnet-peer-request-queue qos))))
    ;; Like Geth, a newly tracked peer starts at the 20-second RTT ceiling, so
    ;; the cold pool permits a 60-second request while it learns real service
    ;; times instead of collapsing on one tiny response.
    (is (= 60d0
           (ethereum-lisp.cli::devnet-snap-qos-target-timeout qos)))
    ;; Each first response contributes ten percent to its 20-second inherited
    ;; RTT. Geth does not replace the cached pool RTT on every packet, and the
    ;; first nine peer joins have detuned confidence to 1/9, so the deadline
    ;; remains at its 60-second cap before the periodic tuner runs.
    (loop for queue in queues
          for rtt from 1d0 by 0.5d0
          do (ethereum-lisp.cli::devnet-peer-request-queue-record-round-trip
              queue rtt))
    (is (< (abs (- (/ 1d0 9d0)
                   (ethereum-lisp.cli::devnet-snap-qos-confidence qos)))
           1d-12))
    (is (= 60d0
           (ethereum-lisp.cli::devnet-snap-qos-target-timeout qos)))
    ;; Force one due tuning interval. The live fast-side median is 18.3s;
    ;; Geth's 0.25 cache impact moves 20 -> 19.575. With confidence pinned to
    ;; one for this oracle, the resulting timeout is exactly 58.725 seconds.
    (setf (ethereum-lisp.cli::devnet-snap-qos-confidence qos) 1d0
          (ethereum-lisp.cli::devnet-snap-qos-tuned-at qos)
          (- (get-internal-real-time)
             (* 21 internal-time-units-per-second)))
    (is (< (abs
            (- 58.725d0
               (ethereum-lisp.cli::devnet-snap-qos-target-timeout qos)))
           1d-9))
    (let* ((probe (first queues))
           (job
             (ethereum-lisp.cli::make-devnet-peer-request-job
              (lambda () nil)
              :snap-response-id
              ethereum-lisp.snap:+snap-message-account-range+
              :snap-request-id 909)))
      ;; Once this response type has one fast successful delivery, its own
      ;; service-time floor (20 -> 18.1 seconds, hence 54.3 seconds) no longer
      ;; dominates the tuned 58.725-second pool deadline.
      (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
       probe ethereum-lisp.snap:+snap-message-account-range+ 1000 1d0)
      (setf (ethereum-lisp.cli::devnet-peer-request-queue-pending probe)
            (list job))
      (is (eq job
              (ethereum-lisp.cli::devnet-peer-request-queue-take-eligible
               probe)))
      (is (< (abs
              (- 58.725d0
                 (ethereum-lisp.cli::devnet-peer-request-job-timeout-seconds
                  job)))
             1d-9))
      (is (< (abs
              (- 58.725d0
                 (- (ethereum-lisp.cli::devnet-peer-request-job-deadline job)
                    (ethereum-lisp.cli::devnet-peer-request-job-started-at
                     job))))
             1d-9))
      (setf (ethereum-lisp.cli::devnet-peer-request-queue-active probe) nil))
    ;; Closing peers removes their RTT and throughput snapshots. Like Geth,
    ;; untracking alone does not rewrite the already tuned cache.
    (dolist (queue (subseq queues 0 5))
      (ethereum-lisp.cli::devnet-peer-request-queue-close queue))
    (is (= 11 (hash-table-count
               (ethereum-lisp.cli::devnet-snap-qos-round-trips qos))))
    (is (= 11 (hash-table-count
               (ethereum-lisp.cli::devnet-snap-qos-throughputs qos))))
    (is (< (abs
            (- 58.725d0
               (ethereum-lisp.cli::devnet-snap-qos-target-timeout qos)))
           1d-9))
    ;; The live median still clamps peer samples to Geth's 2--20s interval.
    (let ((low (first (last queues)))
          (high (second (last queues 2))))
      (clrhash (ethereum-lisp.cli::devnet-snap-qos-round-trips qos))
      (setf (gethash low
                     (ethereum-lisp.cli::devnet-snap-qos-round-trips qos))
            0.1d0)
      (is (= 6d0
             (* 3d0
                (ethereum-lisp.cli::devnet-snap-qos-live-median-round-trip-locked
                 qos))))
      (clrhash (ethereum-lisp.cli::devnet-snap-qos-round-trips qos))
      (setf (gethash high
                     (ethereum-lisp.cli::devnet-snap-qos-round-trips qos))
            90d0)
      (is (= 60d0
             (* 3d0
                (ethereum-lisp.cli::devnet-snap-qos-live-median-round-trip-locked
                 qos))))))
  #-sbcl
  (is t))

(deftest devnet-snap-message-rtt-prevents-cross-type-timeout-collapse
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((qos (ethereum-lisp.cli::make-devnet-snap-qos))
         (queue (ethereum-lisp.cli::make-devnet-peer-request-queue qos))
         (storage-id ethereum-lisp.snap:+snap-message-storage-ranges+))
    ;; Fast message kinds may tune the shared pool to its two-second floor
    ;; before this peer ever requests StorageRanges. The first storage rate must
    ;; nevertheless be cold because it has no storage service-time sample yet.
    (setf (ethereum-lisp.cli::devnet-snap-qos-round-trip qos) 2d0
          (ethereum-lisp.cli::devnet-snap-qos-confidence qos) 1d0
          (ethereum-lisp.cli::devnet-snap-qos-tuned-at qos)
          (get-internal-real-time)
          (ethereum-lisp.cli::devnet-peer-request-queue-snap-round-trip queue)
          2d0)
    (ethereum-lisp.cli::devnet-peer-request-queue-snap-capacity
     queue storage-id)
    (flet ((storage-timeout ()
             (sb-thread:with-mutex
                 ((ethereum-lisp.cli::devnet-peer-request-queue-lock queue))
               (ethereum-lisp.cli::devnet-peer-snap-message-timeout-locked
                queue storage-id))))
      (is (= 6d0 (ethereum-lisp.cli::devnet-snap-qos-target-timeout qos)))
      (is (= 60d0 (storage-timeout)))
      ;; One successful ten-second storage delivery moves only this message
      ;; EWMA from 20 to 19 seconds, hence a 57-second bounded deadline.
      (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
       queue storage-id 1000 10d0)
      (is (< (abs (- 57d0 (storage-timeout))) 1d-12))
      ;; A timeout records zero throughput but must not ratchet the service
      ;; time upward or discard its last successful observation.
      (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
       queue storage-id 0 57d0)
      (is (< (abs (- 57d0 (storage-timeout))) 1d-12))
      (is (< (abs
              (- 57d0
                 (nth-value
                  3
                  (ethereum-lisp.cli::devnet-peer-request-queue-snap-statistics
                   queue storage-id))))
             1d-12))
      (let ((job
              (ethereum-lisp.cli::make-devnet-peer-request-job
               (lambda () nil)
               :snap-response-id storage-id
               :snap-request-id 910)))
        (setf (ethereum-lisp.cli::devnet-peer-request-queue-pending queue)
              (list job))
        (is (eq job
                (ethereum-lisp.cli::devnet-peer-request-queue-take-eligible
                 queue)))
        (is (< (abs
                (- 57d0
                   (ethereum-lisp.cli::devnet-peer-request-job-timeout-seconds
                    job)))
               1d-12))
        (setf (ethereum-lisp.cli::devnet-peer-request-queue-active queue) nil))
      ;; Repeated fast full-size deliveries can legitimately decay the
      ;; message RTT, but their global-deadline assignment is already clamped
      ;; to 512 KiB. Retain bounded decode headroom without enlarging it.
      (dotimes (index 50)
        (declare (ignore index))
        (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
         queue storage-id
         ethereum-lisp.cli::+devnet-snap-max-request-bytes+ 1d0))
      (is (< (abs (- 30d0 (storage-timeout))) 1d-12))
      (is (= ethereum-lisp.cli::+devnet-snap-max-request-bytes+
             (ethereum-lisp.cli::devnet-peer-request-queue-snap-capacity
              queue storage-id)))
      (let ((job
              (ethereum-lisp.cli::make-devnet-peer-request-job
               (lambda () nil)
               :snap-response-id storage-id
               :snap-request-id 911)))
        (setf (ethereum-lisp.cli::devnet-peer-request-queue-pending queue)
              (list job))
        (is (eq job
                (ethereum-lisp.cli::devnet-peer-request-queue-take-eligible
                 queue)))
        (is (< (abs
                (- 30d0
                   (ethereum-lisp.cli::devnet-peer-request-job-timeout-seconds
                    job)))
               1d-12))
        (setf (ethereum-lisp.cli::devnet-peer-request-queue-active queue) nil))
      ;; A timeout resets throughput, so the next 64 KiB probe returns to the
      ;; six-second pool deadline instead of holding a dead peer for 30 seconds.
      (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
       queue storage-id 0 30d0)
      (is (< (abs (- 6d0 (storage-timeout))) 1d-12))))
  #-sbcl
  (is t))

(deftest devnet-snap-new-peer-inherits-live-pool-throughputs
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((qos (ethereum-lisp.cli::make-devnet-snap-qos))
         (first (ethereum-lisp.cli::make-devnet-peer-request-queue qos))
         (range-id ethereum-lisp.snap:+snap-message-account-range+)
         (code-id ethereum-lisp.snap:+snap-message-bytecodes+)
         (minimum ethereum-lisp.cli::+devnet-snap-min-request-bytes+))
    (let ((range-capacity
            (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
             first range-id minimum 3d0)))
      (is (< minimum range-capacity))
      (is (< range-capacity
             ethereum-lisp.cli::+devnet-snap-max-request-bytes+))
      (is (= 2
             (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
              first code-id 1 12d0)))
      (let ((second
              (ethereum-lisp.cli::make-devnet-peer-request-queue qos)))
        ;; Geth seeds a new peer tracker from the live mean throughput instead
        ;; of copying a capacity tied to one obsolete timeout.
        (is (= range-capacity
               (ethereum-lisp.cli::devnet-peer-request-queue-snap-capacity
                second range-id)))
        (is (= 2
               (ethereum-lisp.cli::devnet-peer-request-queue-snap-capacity
                second code-id)))
        (ethereum-lisp.cli::devnet-peer-request-queue-close second))
      (ethereum-lisp.cli::devnet-peer-request-queue-close first)))
  #-sbcl
  (is t))

(deftest devnet-snap-source-applies-learned-range-byte-caps
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((queue (ethereum-lisp.cli::make-devnet-peer-request-queue))
         (limit (* 512 1024))
         (root (make-byte-vector 32))
         (storage-accounts
           (loop for index below 200 collect (snap-test-index-hash index)))
         (account
           (ethereum-lisp.snap:make-snap-get-account-range
            1 root root root limit))
         (storage
           (ethereum-lisp.snap:make-snap-get-storage-ranges
            1 root storage-accounts (make-byte-vector 0) (make-byte-vector 0)
            limit)))
    (ethereum-lisp.cli::devnet-peer-apply-adaptive-snap-byte-cap
     queue ethereum-lisp.snap:+snap-message-get-account-range+ account)
    (ethereum-lisp.cli::devnet-peer-apply-adaptive-snap-byte-cap
     queue ethereum-lisp.snap:+snap-message-get-storage-ranges+ storage)
    (is (= ethereum-lisp.cli::+devnet-snap-min-request-bytes+
           (ethereum-lisp.snap:snap-get-account-range-bytes account)))
    (is (= ethereum-lisp.cli::+devnet-snap-min-request-bytes+
           (ethereum-lisp.snap:snap-get-storage-ranges-bytes storage)))
    (is (= 64
           (length
            (ethereum-lisp.snap:snap-get-storage-ranges-accounts storage))))
    (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
     queue ethereum-lisp.snap:+snap-message-account-range+
     ethereum-lisp.cli::+devnet-snap-min-request-bytes+ 0.05d0)
    (let ((next
            (ethereum-lisp.snap:make-snap-get-account-range
             2 root root root limit)))
      (ethereum-lisp.cli::devnet-peer-apply-adaptive-snap-byte-cap
       queue ethereum-lisp.snap:+snap-message-get-account-range+ next)
      (is (= limit
             (ethereum-lisp.snap:snap-get-account-range-bytes next))))
    (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
     queue ethereum-lisp.snap:+snap-message-storage-ranges+
     ethereum-lisp.cli::+devnet-snap-min-request-bytes+ 0.05d0)
    (let ((next
            (ethereum-lisp.snap:make-snap-get-storage-ranges
             2 root storage-accounts
             (make-byte-vector 0) (make-byte-vector 0) limit)))
      (ethereum-lisp.cli::devnet-peer-apply-adaptive-snap-byte-cap
       queue ethereum-lisp.snap:+snap-message-get-storage-ranges+ next)
      (is (= limit
             (ethereum-lisp.snap:snap-get-storage-ranges-bytes next)))
      (is (= 200
             (length
              (ethereum-lisp.snap:snap-get-storage-ranges-accounts next))))))
  #-sbcl
  (is t))

(deftest devnet-snap-bytecode-assignment-learns-item-capacity
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((queue (ethereum-lisp.cli::make-devnet-peer-request-queue))
         (hashes
           (loop for index below 100 collect (snap-test-index-hash index)))
         (response-id ethereum-lisp.snap:+snap-message-bytecodes+))
    (multiple-value-bind (packet requested)
        (ethereum-lisp.cli::devnet-peer-bytecode-request
         queue hashes (* 512 1024))
      (is (= 1 (length requested)))
      (is (= 1
             (length
              (ethereum-lisp.snap:snap-get-bytecodes-hashes packet)))))
    ;; ByteCodes capacity is measured in delivered code items. Geth's first
    ;; fast sample can reach 84 immediately; the old double-step limiter could
    ;; not, and treating payload bytes as a hash count would overshoot wildly.
    (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
     queue response-id 84 0.05d0)
    (is (= ethereum-lisp.cli::+devnet-snap-max-bytecode-hashes+
           (ethereum-lisp.cli::devnet-peer-request-queue-snap-capacity
            queue response-id)))
    (multiple-value-bind (packet requested)
        (ethereum-lisp.cli::devnet-peer-bytecode-request
         queue hashes (* 512 1024))
      (is (= 84 (length requested)))
      (is (= 84
             (length
              (ethereum-lisp.snap:snap-get-bytecodes-hashes packet))))))
  #-sbcl
  (is t))

(deftest devnet-snap-bytecode-capacity-escapes-target-time-minimum
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((queue (ethereum-lisp.cli::make-devnet-peer-request-queue))
         (response-id ethereum-lisp.snap:+snap-message-bytecodes+)
         (target ethereum-lisp.cli::+devnet-snap-request-target-seconds+))
    ;; The old ROUND(1.05 * throughput * two-seconds) formula remained at one
    ;; after an ordinary one-item response took the whole target interval.
    ;; Geth's explicit +1/ceiling probe must make forward progress instead.
    (is (= 2
           (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
            queue response-id 1 target)))
    (is (= 2
           (ethereum-lisp.cli::devnet-peer-request-queue-snap-capacity
            queue response-id)))
    (multiple-value-bind (packet requested)
        (ethereum-lisp.cli::devnet-peer-bytecode-request
         queue
         (loop for index below 4 collect (snap-test-index-hash index))
         (* 512 1024))
      (is (= 2 (length requested)))
      (is (= 2
             (length
              (ethereum-lisp.snap:snap-get-bytecodes-hashes packet))))))
  #-sbcl
  (is t))

(deftest devnet-snap-source-pool-prefers-capacity-and-independent-type-slots
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (queue-one (ethereum-lisp.cli::make-devnet-peer-request-queue))
         (queue-two (ethereum-lisp.cli::make-devnet-peer-request-queue))
         (entry-one
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "pool-peer-1" :request-queue queue-one))
         (entry-two
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "pool-peer-2" :request-queue queue-two))
         (pool (ethereum-lisp.cli::make-devnet-snap-source-pool node))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) request)
            :storage-ranges (lambda (request) request)
            :bytecodes (lambda (request) request)
            :trie-nodes (lambda (request) request)))
         (storage-id ethereum-lisp.snap:+snap-message-storage-ranges+)
         (bytecode-id ethereum-lisp.snap:+snap-message-bytecodes+))
    (ethereum-lisp.cli::devnet-snap-source-pool-register
     pool entry-one source)
    (ethereum-lisp.cli::devnet-snap-source-pool-register
     pool entry-two source)
    ;; Peer one has the lower latency. Peer two has proved twice its storage
    ;; delivery capacity, so geth-style capacity ordering must still choose it.
    (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
     queue-one storage-id
     ethereum-lisp.cli::+devnet-snap-min-request-bytes+ 0.2d0)
    (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
     queue-two storage-id
     ethereum-lisp.cli::+devnet-snap-min-request-bytes+ 0.25d0)
    (ethereum-lisp.cli::devnet-peer-request-queue-record-snap-delivery
     queue-two storage-id
     (* 2 ethereum-lisp.cli::+devnet-snap-min-request-bytes+) 0.25d0)
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (list entry-one entry-two))))
     (lambda ()
       (multiple-value-bind (first first-source)
           (ethereum-lisp.cli::devnet-snap-source-pool-acquire
            pool storage-id)
         (is (eq entry-two first))
         (is (eq source first-source))
         (multiple-value-bind (second second-source)
             (ethereum-lisp.cli::devnet-snap-source-pool-acquire
              pool storage-id)
           ;; A response type has one slot per peer. The second storage request
           ;; uses the other idle peer instead of prequeueing behind peer two.
           (is (eq entry-one second))
           (is (eq source second-source))
           ;; Response types have independent reservations: bytecode can use
           ;; an idle type slot while both storage slots are occupied.
           (multiple-value-bind (code-entry code-source)
               (ethereum-lisp.cli::devnet-snap-source-pool-acquire
                pool bytecode-id)
             (is (eq entry-one code-entry))
             (is (eq source code-source))
             (ethereum-lisp.cli::devnet-snap-source-pool-release
              pool code-entry bytecode-id))
           ;; Once all storage slots are occupied, new work stays in the
           ;; global scheduler until an actual peer becomes idle.
           (let* ((attempted (sb-thread:make-semaphore :count 0))
                  (waiter
                    (sb-thread:make-thread
                     (lambda ()
                       (sb-thread:signal-semaphore attempted)
                       (multiple-value-list
                        (ethereum-lisp.cli::devnet-snap-source-pool-acquire
                         pool storage-id)))
                     :name "snap-source-pool-idle-wait")))
             (sb-thread:wait-on-semaphore attempted :timeout 5)
             (is (eq :blocked
                     (sb-thread:join-thread
                      waiter :timeout 0.1 :default :blocked)))
             (ethereum-lisp.cli::devnet-snap-source-pool-release
              pool first storage-id)
             (let ((selection
                     (sb-thread:join-thread
                      waiter :timeout 5 :default :timeout)))
               (is (not (eq :timeout selection)))
               (is (eq entry-two (first selection)))
               (is (eq source (second selection)))
               (ethereum-lisp.cli::devnet-snap-source-pool-release
                pool (first selection) storage-id)))
           (ethereum-lisp.cli::devnet-snap-source-pool-release
            pool second storage-id))
       ;; Once idle again, learned capacity wins the storage tie.
       (multiple-value-bind (selected selected-source)
           (ethereum-lisp.cli::devnet-snap-source-pool-acquire
            pool storage-id)
         (is (eq entry-two selected))
         (is (eq source selected-source))
         (ethereum-lisp.cli::devnet-snap-source-pool-release
          pool selected storage-id))))))
  #-sbcl
  (is t))

(deftest devnet-snap-source-pool-retries-a-dependency-on-another-peer
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (entry-one
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "failing-dependency-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (entry-two
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "healthy-dependency-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (pool (ethereum-lisp.cli::make-devnet-snap-source-pool node))
         (failed-calls 0)
         (healthy-calls 0)
         (failed-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) request)
            :storage-ranges
            (lambda (request)
              (declare (ignore request))
              (incf failed-calls)
              (error "dependency peer retired"))
            :bytecodes (lambda (request) request)
            :trie-nodes (lambda (request) request)))
         (healthy-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) request)
            :storage-ranges
            (lambda (request)
              (incf healthy-calls)
              request)
            :bytecodes (lambda (request) request)
            :trie-nodes (lambda (request) request))))
    (ethereum-lisp.cli::devnet-snap-source-pool-register
     pool entry-one failed-source)
    (ethereum-lisp.cli::devnet-snap-source-pool-register
     pool entry-two healthy-source)
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (list entry-one entry-two))))
     (lambda ()
       (is (eq :request
               (ethereum-lisp.cli::devnet-snap-source-pool-call
                pool ethereum-lisp.snap:+snap-message-storage-ranges+
                #'ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                :request "storage ranges")))
       (is (= 1 failed-calls))
       (is (= 1 healthy-calls))
       ;; The failed transport stays retired, so subsequent dependency work
       ;; does not throw away another already verified account response.
       (is (eq :second
               (ethereum-lisp.cli::devnet-snap-source-pool-call
                pool ethereum-lisp.snap:+snap-message-storage-ranges+
                #'ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                :second "storage ranges")))
       (is (= 1 failed-calls))
       (is (= 2 healthy-calls))
       ;; Expiring the bounded cooldown admits the transport again; a Boolean
       ;; permanent ban would either keep skipping it or break timestamp
       ;; comparison in the selector.
       (setf
        (gethash
         entry-one
         (ethereum-lisp.cli::devnet-snap-source-pool-failed-entries pool))
        0)
       (is (eq :third
               (ethereum-lisp.cli::devnet-snap-source-pool-call
                pool ethereum-lisp.snap:+snap-message-storage-ranges+
                #'ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                :third "storage ranges")))
       (is (= 2 failed-calls))
       (is (= 3 healthy-calls)))))
  #-sbcl
  (is t))

(deftest devnet-snap-source-pool-reuses-a-live-peer-after-request-timeout
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "timeout-dependency-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (pool (ethereum-lisp.cli::make-devnet-snap-source-pool node))
         (calls 0)
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) request)
            :storage-ranges
            (lambda (request)
              (if (= 1 (incf calls))
                  (error
                   'ethereum-lisp.cli::devnet-snap-request-timeout
                   :request-id 17
                   :response-id
                   ethereum-lisp.snap:+snap-message-storage-ranges+
                   :timeout-seconds 6d0)
                  request))
            :bytecodes (lambda (request) request)
            :trie-nodes (lambda (request) request))))
    (ethereum-lisp.cli::devnet-snap-source-pool-register pool entry source)
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (list entry))))
     (lambda ()
       (is (eq :request
               (ethereum-lisp.cli::devnet-snap-source-pool-call
                pool ethereum-lisp.snap:+snap-message-storage-ranges+
                #'ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                :request "storage ranges")))
       (is (= 2 calls))
       ;; A single request expiry resets per-message capacity but never enters
       ;; the whole-peer transport cooldown table.
       (is (not
            (nth-value
             1
             (gethash
              entry
              (ethereum-lisp.cli::devnet-snap-source-pool-failed-entries
               pool))))))))
  #-sbcl
  (is t))

(deftest devnet-snap-source-pool-waits-for-a-cooled-transport
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (empty-node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "cooled-dependency-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (pool (ethereum-lisp.cli::make-devnet-snap-source-pool node))
         (empty-pool
           (ethereum-lisp.cli::make-devnet-snap-source-pool empty-node))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) request)
            :storage-ranges (lambda (request) request)
            :bytecodes (lambda (request) request)
            :trie-nodes (lambda (request) request)))
         (response-id ethereum-lisp.snap:+snap-message-bytecodes+))
    (ethereum-lisp.cli::devnet-snap-source-pool-register pool entry source)
    (setf
     (gethash
      entry (ethereum-lisp.cli::devnet-snap-source-pool-failed-entries pool))
     (+ (get-universal-time) 3600))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is snap-only-p)
              (cond
                ((eq node seen-node) (list entry))
                ((eq empty-node seen-node) nil)
                (t (error "Unexpected source-pool node"))))))
     (lambda ()
       ;; A genuinely empty pool remains an immediate availability result.
       (multiple-value-bind (selected selected-source)
           (ethereum-lisp.cli::devnet-snap-source-pool-acquire
            empty-pool response-id)
         (is (null selected))
         (is (null selected-source)))
       (let* ((attempted (sb-thread:make-semaphore :count 0))
              (waiter
                (sb-thread:make-thread
                 (lambda ()
                   (sb-thread:signal-semaphore attempted)
                   (multiple-value-list
                    (ethereum-lisp.cli::devnet-snap-source-pool-acquire
                     pool response-id)))
                 :name "snap-source-pool-cooldown-wait")))
         (sb-thread:wait-on-semaphore attempted :timeout 5)
         ;; The pre-fix implementation returned (NIL NIL) immediately here,
         ;; misclassifying a bounded cooldown as total source exhaustion.
         (is (eq :blocked
                 (sb-thread:join-thread
                  waiter :timeout 0.1 :default :blocked)))
         (sb-thread:with-mutex
             ((ethereum-lisp.cli::devnet-snap-source-pool-lock pool))
           (setf
            (gethash
             entry
             (ethereum-lisp.cli::devnet-snap-source-pool-failed-entries pool))
            0)
           (sb-thread:condition-broadcast
            (ethereum-lisp.cli::devnet-snap-source-pool-waitqueue
             pool response-id)))
         (let ((selection
                 (sb-thread:join-thread
                  waiter :timeout 5 :default :timeout)))
           (is (not (eq :timeout selection)))
           (is (eq entry (first selection)))
           (is (eq source (second selection)))
           (ethereum-lisp.cli::devnet-snap-source-pool-release
            pool entry response-id))))))
  #-sbcl
  (is t))

(deftest devnet-snap-source-pool-adopts-a-new-live-dependency-peer
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (old-entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "cooled-registered-dependency-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (new-entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "new-live-dependency-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (pool (ethereum-lisp.cli::make-devnet-snap-source-pool node))
         (old-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) request)
            :storage-ranges (lambda (request) request)
            :bytecodes (lambda (request) request)
            :trie-nodes (lambda (request) request)))
         (new-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) request)
            :storage-ranges (lambda (request) request)
            :bytecodes (lambda (request) request)
            :trie-nodes (lambda (request) request)))
         (response-id ethereum-lisp.snap:+snap-message-storage-ranges+)
         (built 0))
    (ethereum-lisp.cli::devnet-snap-source-pool-register
     pool old-entry old-source)
    (setf
     (gethash
      old-entry
      (ethereum-lisp.cli::devnet-snap-source-pool-failed-entries pool))
     (+ (get-universal-time) 3600))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (list old-entry new-entry)))
      (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
            (lambda (entry)
              (is (eq new-entry entry))
              (incf built)
              new-source)))
     (lambda ()
       ;; No account-page result has registered NEW-ENTRY. The dependency
       ;; selector must adopt it immediately instead of sleeping until the old
       ;; transport's one-hour cooldown expires.
       (multiple-value-bind (selected selected-source)
           (ethereum-lisp.cli::devnet-snap-source-pool-acquire
            pool response-id)
         (is (eq new-entry selected))
         (is (eq new-source selected-source))
         (is (= 1 built))
         (is
          (eq new-source
              (gethash
               new-entry
               (ethereum-lisp.cli::devnet-snap-source-pool-fixed-sources
                pool))))
         (ethereum-lisp.cli::devnet-snap-source-pool-release
          pool selected response-id)))))
  #-sbcl
  (is t))

(deftest devnet-snap-source-pool-yields-a-stale-pruned-pivot
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (entry
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "stale-pruned-dependency-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (pivot (make-hash32 (make-byte-vector 32 :initial-element 72)))
         (pool (ethereum-lisp.cli::make-devnet-snap-source-pool node pivot))
         (requests 0)
         (stale-checks 0)
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) request)
            :storage-ranges
            (lambda (request)
              (declare (ignore request))
              (incf requests)
              (ethereum-lisp.snap-sync:snap-sync-state-unavailable
               "storage-range"))
            :bytecodes (lambda (request) request)
            :trie-nodes (lambda (request) request))))
    (setf
     (ethereum-lisp.cli::devnet-snap-source-pool-stale-function pool)
     (lambda () (incf stale-checks) t))
    (ethereum-lisp.cli::devnet-snap-source-pool-register pool entry source)
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (list entry))))
     (lambda ()
       (signals ethereum-lisp.snap-sync:snap-sync-heal-yielded
         (ethereum-lisp.cli::devnet-snap-source-pool-call
          pool ethereum-lisp.snap:+snap-message-storage-ranges+
          #'ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
          :request "storage ranges"))))
    (is (= 1 requests))
    (is (= 1 stale-checks))
    (is
     (ethereum-lisp.cli::devnet-node-snap-pivot-peer-unavailable-p
      node pivot entry)))
  #-sbcl
  (is t))

(deftest devnet-snap-source-pool-does-not-readmit-state-unavailable-peer
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (exhausted-node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (entry-one
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "pruned-dependency-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (entry-two
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "stateful-dependency-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (pivot
           (make-hash32 (make-byte-vector 32 :initial-element 73)))
         (pool
           (ethereum-lisp.cli::make-devnet-snap-source-pool node pivot))
         (exhausted-pool
           (ethereum-lisp.cli::make-devnet-snap-source-pool
            exhausted-node pivot))
         (pruned-calls 0)
         (stateful-calls 0)
         (pruned-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) request)
            :storage-ranges
            (lambda (request)
              (declare (ignore request))
              (incf pruned-calls)
              (ethereum-lisp.snap-sync:snap-sync-state-unavailable
               "storage-range"))
            :bytecodes (lambda (request) request)
            :trie-nodes (lambda (request) request)))
         (stateful-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) request)
            :storage-ranges
            (lambda (request)
              (incf stateful-calls)
              request)
            :bytecodes (lambda (request) request)
            :trie-nodes (lambda (request) request))))
    (ethereum-lisp.cli::devnet-snap-source-pool-register
     pool entry-one pruned-source)
    (ethereum-lisp.cli::devnet-snap-source-pool-register
     pool entry-two stateful-source)
    (ethereum-lisp.cli::devnet-snap-source-pool-register
     exhausted-pool entry-one pruned-source)
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is snap-only-p)
              (cond
                ((eq node seen-node) (list entry-one entry-two))
                ((eq exhausted-node seen-node) (list entry-one))
                (t (error "Unexpected source-pool node"))))))
     (lambda ()
       (is (eq :first
               (ethereum-lisp.cli::devnet-snap-source-pool-call
                pool ethereum-lisp.snap:+snap-message-storage-ranges+
                #'ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                :first "storage ranges")))
       (is (= 1 pruned-calls))
       (is (= 1 stateful-calls))
       (is
        (ethereum-lisp.cli::devnet-node-snap-pivot-peer-unavailable-p
         node pivot entry-one))
       (is (not
            (ethereum-lisp.cli::devnet-node-snap-pivot-peer-unavailable-p
             node pivot entry-two)))
       ;; Expiring ordinary cooldown state cannot readmit an explicit pruning
       ;; rejection during the same pivot import.
       (setf
        (gethash
         entry-one
         (ethereum-lisp.cli::devnet-snap-source-pool-failed-entries pool))
        0)
       (is (eq :second
               (ethereum-lisp.cli::devnet-snap-source-pool-call
                pool ethereum-lisp.snap:+snap-message-storage-ranges+
                #'ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
                :second "storage ranges")))
       (is (= 1 pruned-calls))
       (is (= 2 stateful-calls))
       ;; Aggregate dependency exhaustion is a distinct subtype, so the
       ;; account worker which happened to own this page is not blamed for the
       ;; dependency transports' exact pruning responses.
       (signals ethereum-lisp.cli::devnet-snap-pooled-state-unavailable
         (ethereum-lisp.cli::devnet-snap-source-pool-call
          exhausted-pool ethereum-lisp.snap:+snap-message-storage-ranges+
          #'ethereum-lisp.snap-sync:snap-sync-source-storage-ranges
          :exhausted "storage ranges"))
       (is (= 2 pruned-calls)))))
  #-sbcl
  (is t))

(deftest devnet-snap-source-pool-validates-bytecodes-before-peer-release
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (entry-one
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "invalid-bytecode-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (entry-two
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "valid-bytecode-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (pivot (make-hash32 (make-byte-vector 32 :initial-element 75)))
         (pool (ethereum-lisp.cli::make-devnet-snap-source-pool node pivot))
         (code (hex-to-bytes "60006000f3"))
         (hash (keccak-256 code))
         (invalid-calls 0)
         (valid-calls 0)
         (invalid-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) request)
            :storage-ranges (lambda (request) request)
            :bytecodes
            (lambda (request)
              (incf invalid-calls)
              ;; Returning the response is transport success. Only the
              ;; client's hash/state verifier can classify it as unusable.
              (ethereum-lisp.snap:make-snap-bytecodes
               (ethereum-lisp.snap:snap-get-bytecodes-id request) '()))
            :trie-nodes (lambda (request) request)))
         (valid-source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range (lambda (request) request)
            :storage-ranges (lambda (request) request)
            :bytecodes
            (lambda (request)
              (incf valid-calls)
              (ethereum-lisp.snap:make-snap-bytecodes
               (ethereum-lisp.snap:snap-get-bytecodes-id request)
               (list code)))
            :trie-nodes (lambda (request) request)))
         (pooled-source nil))
    (devnet-peer-sync-call-with-function-overrides
     (list
      (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
            (lambda (seen-node &key snap-only-p)
              (is (eq node seen-node))
              (is snap-only-p)
              (list entry-one entry-two)))
      (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
            (lambda (entry)
              (cond
                ((eq entry entry-one) invalid-source)
                ((eq entry entry-two) valid-source)
                (t (error "Unexpected source-pool entry"))))))
     (lambda ()
       (setf pooled-source
             (ethereum-lisp.cli::devnet-snap-source-pool-source
              pool entry-one))
       ;; Registration is separate from range ownership. The verified
       ;; ByteCodes callback below may select this second transport even
       ;; though POOLED-SOURCE belongs to ENTRY-ONE's account worker.
       (ethereum-lisp.cli::devnet-snap-source-pool-source pool entry-two)
       (multiple-value-bind (codes requested)
           (ethereum-lisp.snap-sync::snap-sync-fetch-code-request
            pooled-source (list hash) (* 512 1024))
         (is (= 1 (length codes)))
         (is (= 1 (length requested)))
         (is (bytes= hash (caar codes)))
         (is (bytes= code (cdar codes))))
       (is (= 1 invalid-calls))
       (is (= 1 valid-calls))
       (is
        (gethash
         entry-one
         (ethereum-lisp.cli::devnet-snap-source-pool-unavailable-entries
          pool)))
       (is (not
            (gethash
             entry-two
             (ethereum-lisp.cli::devnet-snap-source-pool-unavailable-entries
              pool)))))))
  #-sbcl
  (is t))

(deftest devnet-snap-source-pool-validates-storage-before-release-and-materializes-after
  (:layer :integration :module :p2p)
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (entry-one
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "invalid-storage-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (entry-two
           (ethereum-lisp.cli::make-devnet-peer-entry
            :id-hex "valid-storage-peer"
            :request-queue
            (ethereum-lisp.cli::make-devnet-peer-request-queue)))
         (pivot (make-hash32 (make-byte-vector 32 :initial-element 76)))
         (pool (ethereum-lisp.cli::make-devnet-snap-source-pool node pivot))
         (source-state (make-state-db))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (address
           (address-from-hex
            "0x0000000000000000000000000000000000000042"))
         (slot (make-hash32 (make-byte-vector 32 :initial-element 41)))
         (invalid-calls 0)
         (valid-calls 0))
    (state-db-set-storage source-state address slot 256)
    (let* ((state-root (state-db-root source-state))
           (storage-root (state-db-get-storage-root source-state address))
           (commitment
             (cons (keccak-256 (address-bytes address)) storage-root))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              source-database source-state))
           (invalid-source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range (lambda (request) request)
              :storage-ranges
              (lambda (request)
                (incf invalid-calls)
                (ethereum-lisp.snap:make-snap-storage-ranges
                 (ethereum-lisp.snap:snap-get-storage-ranges-id request)
                 '() '()))
              :bytecodes (lambda (request) request)
              :trie-nodes (lambda (request) request)))
           (valid-source
             (ethereum-lisp.snap-sync:make-snap-sync-source
              :account-range (lambda (request) request)
              :storage-ranges
              (lambda (request)
                (incf valid-calls)
                (multiple-value-bind (response-id encoded)
                    (ethereum-lisp.snap:snap-serve-request
                     backend
                     ethereum-lisp.snap:+snap-message-get-storage-ranges+
                     (ethereum-lisp.snap:encode-snap-message
                      ethereum-lisp.snap:+snap-message-get-storage-ranges+
                      request))
                  (ethereum-lisp.snap:decode-snap-message
                   response-id encoded)))
              :bytecodes (lambda (request) request)
              :trie-nodes (lambda (request) request)))
           (pooled-source nil)
           (materialized-after-release-p nil)
           (materialize-name
             'ethereum-lisp.snap-sync::snap-sync-populate-verified-storage-group)
           (real-materialize (fdefinition materialize-name)))
      (devnet-peer-sync-call-with-function-overrides
       (list
        (cons 'ethereum-lisp.cli::devnet-node-live-sync-entries
              (lambda (seen-node &key snap-only-p)
                (is (eq node seen-node))
                (is snap-only-p)
                (list entry-one entry-two)))
        (cons 'ethereum-lisp.cli::devnet-peer-queued-snap-source
              (lambda (entry)
                (cond
                  ((eq entry entry-one) invalid-source)
                  ((eq entry entry-two) valid-source)
                  (t (error "Unexpected source-pool entry")))))
        (cons materialize-name
              (lambda (database batch root group)
                ;; Both the rejected peer and the successful retry must have
                ;; released their StorageRanges reservation before authenticated
                ;; trie records and subtree metadata are materialized locally.
                (dolist (entry (list entry-one entry-two))
                  (is
                   (zerop
                    (gethash
                     ethereum-lisp.snap:+snap-message-storage-ranges+
                     (ethereum-lisp.cli::
                      devnet-snap-source-pool-reservation-table pool entry)
                     0))))
                (setf materialized-after-release-p t)
                (funcall real-materialize database batch root group))))
       (lambda ()
         (setf pooled-source
               (ethereum-lisp.cli::devnet-snap-source-pool-source
                pool entry-one))
         (ethereum-lisp.cli::devnet-snap-source-pool-source pool entry-two)
         (multiple-value-bind (received open-commitment)
             (ethereum-lisp.snap-sync::
              snap-sync-fetch-storage-commitment-request
              target-database pooled-source state-root (list commitment)
              (* 512 1024))
           (is (= 1 received))
           (is (null open-commitment)))
         (is (= 1 invalid-calls))
         (is (= 1 valid-calls))
         (is materialized-after-release-p)
         (is
          (gethash
           entry-one
           (ethereum-lisp.cli::devnet-snap-source-pool-unavailable-entries
            pool)))
         (multiple-value-bind (node-record present-p)
             (ethereum-lisp.trie:trie-node-store-get
              target-database storage-root)
           (is present-p)
           (is (plusp (length node-record))))))))
  #-sbcl
  (is t))

(deftest devnet-snap-pivot-unavailable-cache-retains-concurrent-writers
  (:layer :unit :module :p2p)
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-json *eth-sync-paris-genesis-json*
            :port 0 :public-port 0))
         (pivot
           (make-hash32 (make-byte-vector 32 :initial-element 74)))
         (entries
           (loop for index below 32
                 collect
                 (ethereum-lisp.cli::make-devnet-peer-entry
                  :id-hex (format nil "concurrent-pruned-peer-~D" index))))
         (threads '()))
    (dolist (entry entries)
      (let ((entry entry))
        (push
         (sb-thread:make-thread
          (lambda ()
            (dotimes (attempt 64)
              (declare (ignore attempt))
              (ethereum-lisp.cli::devnet-node-note-snap-pivot-unavailable
               node pivot entry)))
          :name "snap-unavailable-cache-test-writer")
         threads)))
    (dolist (thread threads)
      (sb-thread:join-thread thread))
    (is
     (every
      (lambda (entry)
        (ethereum-lisp.cli::devnet-node-snap-pivot-peer-unavailable-p
         node pivot entry))
      entries)))
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
