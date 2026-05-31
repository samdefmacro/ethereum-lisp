(in-package #:ethereum-lisp.test)

(defconstant +devnet-cli-genesis-fixture+
  "tests/fixtures/execution-spec-tests/phase-a-shanghai-genesis.json")

(defconstant +devnet-cli-jwt-secret+
  "1111111111111111111111111111111111111111111111111111111111111111")

(defun devnet-cli-temp-path (name type)
  (merge-pathnames
   (make-pathname :name (format nil "~A-~A" name (gensym))
                  :type type)
   #P"/private/tmp/"))

(defun devnet-cli-write-temp-file (path contents)
  (with-open-file (stream path
                          :direction :output
                          :if-exists :supersede
                          :if-does-not-exist :create)
    (write-string contents stream)))

(defun devnet-cli-file-string (path)
  (with-open-file (stream path :direction :input)
    (let ((string (make-string (file-length stream))))
      (read-sequence string stream)
      string)))

(defun make-devnet-cli-one-shot-listener (endpoint)
  (let ((accepted-p nil))
    (make-engine-rpc-http-listener
     :endpoint endpoint
     :accept-function
     (lambda ()
       (unless accepted-p
         (setf accepted-p t)
         (make-engine-rpc-http-connection
          :input-stream
          (make-string-input-stream "GET / HTTP/1.1\r\n\r\n")
          :output-stream (make-string-output-stream)
          :close-function (lambda () nil))))
     :close-function (lambda () nil))))

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
    (is (string= (hash32-to-hex head-hash) (getf summary :head-hash)))
    (is (getf summary :state-available-p))
    (is (not (getf summary :auth-required-p)))
    (is (not (getf summary :jwt-secret-path)))
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
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
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
          (chain-id-response
            (parse-json
             (engine-rpc-handle-request-json
              "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"eth_chainId\",\"params\":[]}"
              engine-store
              engine-config
              :allowed-method-p public-filter))))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field engine-response "error")
              "code")))
      (is (= -32601
             (fixture-object-field
              (fixture-object-field public-response "error")
              "code")))
      (is (string= "0x539"
                   (fixture-object-field chain-id-response "result"))))))

(deftest devnet-node-start-serves-engine-and-public-listeners
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-path +devnet-cli-genesis-fixture+
                :port 8551
                :public-port 8545))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-devnet-cli-one-shot-listener "engine")
            (make-devnet-cli-one-shot-listener "public")
            :max-connections 1)))
    (is (= 1 (getf summary :engine-connections)))
    (is (= 1 (getf summary :public-connections)))
    (is (= 2 (getf summary :total-connections)))))

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

(deftest devnet-cli-main-json-summary-and-ready-file
  (let ((jwt-path (devnet-cli-temp-path "ethereum-lisp-devnet-jwt" "hex"))
        (ready-path (devnet-cli-temp-path "ethereum-lisp-devnet-ready" "json"))
        (output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (is (= 0
                  (ethereum-lisp.cli:main
                   (list "devnet"
                         "--genesis" +devnet-cli-genesis-fixture+
                         "--port" "0"
                         "--public-port" "8546"
                         "--jwt-secret" (namestring jwt-path)
                         "--ready-file" (namestring ready-path)
                         "--json"
                         "--no-serve")
                   :output-stream output
                   :error-stream errors)))
           (is (string= "" (get-output-stream-string errors)))
           (let* ((stdout-summary
                    (parse-json (get-output-stream-string output)))
                  (ready-summary
                    (parse-json (devnet-cli-file-string ready-path))))
             (dolist (summary (list stdout-summary ready-summary))
               (is (= 1337 (fixture-object-field summary "chainId")))
               (is (= 0 (fixture-object-field summary "headNumber")))
               (is (string= "127.0.0.1:0"
                            (fixture-object-field summary "engineEndpoint")))
               (is (string= "127.0.0.1:8546"
                            (fixture-object-field summary "rpcEndpoint")))
               (is (eq t (fixture-object-field summary "authRequired")))
               (is (eq t (fixture-object-field summary "stateAvailable")))
               (is (string= (namestring jwt-path)
                            (fixture-object-field summary "jwtSecretPath"))))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))
      (when (probe-file ready-path)
        (delete-file ready-path)))))

(deftest devnet-cli-rejects-missing-genesis
  (let ((output (make-string-output-stream))
        (errors (make-string-output-stream)))
    (is (= 1
           (ethereum-lisp.cli:main
            (list "devnet" "--no-serve")
            :output-stream output
            :error-stream errors)))
    (is (string= "" (get-output-stream-string output)))
    (is (search "--genesis is required"
                (get-output-stream-string errors)))))

(deftest devnet-cli-rejects-malformed-options-before-loading-genesis
  (labels ((run-error (args)
             (let ((output (make-string-output-stream))
                   (errors (make-string-output-stream)))
               (is (= 1
                      (ethereum-lisp.cli:main
                       args
                       :output-stream output
                       :error-stream errors)))
               (is (string= "" (get-output-stream-string output)))
               (get-output-stream-string errors))))
    (is (search "--port requires an integer value"
                (run-error (list "devnet" "--port" "abc" "--no-serve"))))
    (is (search "--port must be between 0 and 65535"
                (run-error (list "devnet" "--port" "70000" "--no-serve"))))
    (is (search "--public-port requires an integer value"
                (run-error (list "devnet"
                                 "--public-port"
                                 "abc"
                                 "--no-serve"))))
    (is (search "--public-port must be between 0 and 65535"
                (run-error (list "devnet"
                                 "--public-port"
                                 "70000"
                                 "--no-serve"))))
    (is (search "--max-connections must be non-negative"
                (run-error (list "devnet"
                                 "--max-connections"
                                 "-1"
                                 "--no-serve"))))
    (is (search "--genesis requires a value"
                (run-error (list "devnet" "--genesis"))))
    (is (search "--genesis requires a value"
                (run-error (list "devnet" "--genesis" "--no-serve"))))
    (is (search "--host requires a value"
                (run-error (list "devnet" "--host" "--no-serve"))))
    (is (search "--public-host requires a value"
                (run-error (list "devnet" "--public-host" "--no-serve"))))
    (is (search "--port requires a value"
                (run-error (list "devnet" "--port" "--no-serve"))))
    (is (search "--public-port requires a value"
                (run-error (list "devnet" "--public-port" "--no-serve"))))
    (is (search "Unknown option --wat"
                (run-error (list "devnet" "--wat"))))))
