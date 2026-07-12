(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-verify-public-api-allowlist ()
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path
            (namestring
             (devnet-smoke-gate-reference-path
              +devnet-cli-genesis-fixture+))
            :port 8551
            :public-port 8545
            :network-id 7331
            :public-allowed-method-p
            (ethereum-lisp.cli::devnet-cli-public-api-method-filter
             *devnet-smoke-gate-public-api-allowlist*)
            :public-api-modules
            *devnet-smoke-gate-public-api-allowlist*))
         (chain-id-output (make-string-output-stream))
         (network-output (make-string-output-stream))
         (rpc-modules-output (make-string-output-stream))
         (web3-output (make-string-output-stream))
         (txpool-output (make-string-output-stream))
         (engine-output (make-string-output-stream))
         (public-requests
           (list
            (cons (devnet-smoke-gate-json-rpc-request
                   301 "eth_chainId" '())
                  chain-id-output)
            (cons (devnet-smoke-gate-json-rpc-request
                   302 "net_version" '())
                  network-output)
            (cons (devnet-smoke-gate-json-rpc-request
                   306 "rpc_modules" '())
                  rpc-modules-output)
            (cons (devnet-smoke-gate-json-rpc-request
                   303 "web3_clientVersion" '())
                  web3-output)
            (cons (devnet-smoke-gate-json-rpc-request
                   304 "txpool_status" '())
                  txpool-output)
            (cons (devnet-smoke-gate-json-rpc-request
                   305 "engine_exchangeCapabilities" (list #()))
                  engine-output))))
    (let ((summary
            (ethereum-lisp.cli:start-devnet-node-listeners
             node
             (make-engine-rpc-http-listener
              :endpoint "allowlist-engine"
              :accept-function (lambda () nil)
              :close-function (lambda () nil))
             (make-engine-rpc-http-listener
              :endpoint "allowlist-public"
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
             :max-connections
             +devnet-smoke-gate-public-api-allowlist-connections+)))
      (let* ((chain-id-response
               (get-output-stream-string chain-id-output))
             (network-response
               (get-output-stream-string network-output))
             (rpc-modules-response
               (get-output-stream-string rpc-modules-output))
             (web3-response
               (get-output-stream-string web3-output))
             (txpool-response
               (get-output-stream-string txpool-output))
             (engine-response
               (get-output-stream-string engine-output))
             (chain-id-rpc (devnet-smoke-gate-rpc-body chain-id-response))
             (network-rpc (devnet-smoke-gate-rpc-body network-response))
             (rpc-modules-rpc
               (devnet-smoke-gate-rpc-body rpc-modules-response))
             (rpc-modules
               (fixture-object-field rpc-modules-rpc "result"))
             (web3-rpc (devnet-smoke-gate-rpc-body web3-response))
             (txpool-rpc (devnet-smoke-gate-rpc-body txpool-response))
             (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
             (chain-id (fixture-object-field chain-id-rpc "result"))
             (network-version
               (fixture-object-field network-rpc "result"))
             (web3-error-code
               (devnet-smoke-gate-error-code web3-rpc))
             (txpool-error-code
               (devnet-smoke-gate-error-code txpool-rpc))
             (engine-error-code
               (devnet-smoke-gate-error-code engine-rpc))
             (summary-json
               (ethereum-lisp.cli::devnet-node-summary-json-object node))
             (telemetry-fields
               (ethereum-lisp.cli::devnet-node-telemetry-fields node))
             (reported-modules
               (cdr (assoc "publicApiModules"
                           summary-json
                           :test #'string=)))
             (telemetry-modules
               (cdr (assoc "publicApiModules"
                           telemetry-fields
                           :test #'string=))))
        (dolist (response (list chain-id-response network-response
                                rpc-modules-response web3-response
                                txpool-response
                                engine-response))
          (devnet-smoke-gate-require
           (= 200 (devnet-cli-http-status response))
           "Public API allowlist probe HTTP status mismatch"))
        (devnet-smoke-gate-require
         (= 0 (getf summary :engine-connections))
         "Public API allowlist Engine connection count mismatch")
        (devnet-smoke-gate-require
         (= +devnet-smoke-gate-public-api-allowlist-connections+
            (getf summary :public-connections))
         "Public API allowlist public connection count mismatch")
        (devnet-smoke-gate-require
         (string= "0x539" chain-id)
         "Public API allowlist eth_chainId mismatch")
        (devnet-smoke-gate-require
         (string= "7331" network-version)
         "Public API allowlist net_version mismatch")
        (devnet-smoke-gate-require
         (string= "1.0" (fixture-object-field rpc-modules "eth"))
         "Public API allowlist rpc_modules eth module mismatch")
        (devnet-smoke-gate-require
         (string= "1.0" (fixture-object-field rpc-modules "net"))
         "Public API allowlist rpc_modules net module mismatch")
        (devnet-smoke-gate-require
         (string= "1.0" (fixture-object-field rpc-modules "rpc"))
         "Public API allowlist rpc_modules rpc module mismatch")
        (devnet-smoke-gate-require
         (not (fixture-object-field rpc-modules "txpool"))
         "Public API allowlist rpc_modules unexpectedly reported txpool")
        (devnet-smoke-gate-require
         (not (fixture-object-field rpc-modules "web3"))
         "Public API allowlist rpc_modules unexpectedly reported web3")
        (dolist (code (list web3-error-code txpool-error-code
                            engine-error-code))
          (devnet-smoke-gate-require
           (= -32601 code)
           "Public API allowlist did not reject a blocked method"))
        (devnet-smoke-gate-require
         (equal *devnet-smoke-gate-public-api-allowlist*
                reported-modules)
         "Public API allowlist summary modules mismatch")
        (devnet-smoke-gate-require
         (string= "eth,net" telemetry-modules)
         "Public API allowlist telemetry modules mismatch")
        (list :allowed-modules
              (copy-list *devnet-smoke-gate-public-api-allowlist*)
              :reported-modules reported-modules
              :telemetry-modules telemetry-modules
              :rpc-modules rpc-modules
              :engine-connections (getf summary :engine-connections)
              :public-connections (getf summary :public-connections)
              :total-connections (getf summary :total-connections)
              :chain-id chain-id
              :network-version network-version
              :web3-error-code web3-error-code
              :txpool-error-code txpool-error-code
              :engine-error-code engine-error-code))))
  #-sbcl
  (error "Public API allowlist smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-public-cors ()
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path
            (namestring
             (devnet-smoke-gate-reference-path
              +devnet-cli-genesis-fixture+))
            :port 8551
            :public-port 8545
            :public-cors-origins *devnet-smoke-gate-public-cors-origins*))
         (preflight-output (make-string-output-stream))
         (post-output (make-string-output-stream))
         (blocked-output (make-string-output-stream))
         (public-requests
           (list
            (cons
             (devnet-smoke-gate-http-request
              "OPTIONS" "/" :origin "https://runner.example")
             preflight-output)
            (cons
             (devnet-smoke-gate-http-request
              "POST" "/"
              :origin "https://observer.example"
              :content-type "application/json"
              :body (devnet-smoke-gate-json-rpc-request
                     401 "eth_chainId" '()))
             post-output)
            (cons
             (devnet-smoke-gate-http-request
              "OPTIONS" "/" :origin "https://blocked.example")
             blocked-output))))
    (let ((summary
            (ethereum-lisp.cli:start-devnet-node-listeners
             node
             (make-engine-rpc-http-listener
              :endpoint "cors-engine"
              :accept-function (lambda () nil)
              :close-function (lambda () nil))
             (make-engine-rpc-http-listener
              :endpoint "cors-public"
              :accept-function
              (lambda ()
                (when public-requests
                  (destructuring-bind (request . output)
                      (pop public-requests)
                    (make-engine-rpc-http-connection
                     :input-stream (make-string-input-stream request)
                     :output-stream output
                     :close-function (lambda () nil)))))
              :close-function (lambda () nil))
             :max-connections +devnet-smoke-gate-public-cors-connections+)))
      (let* ((preflight-response
               (get-output-stream-string preflight-output))
             (post-response
               (get-output-stream-string post-output))
             (blocked-response
               (get-output-stream-string blocked-output))
             (post-rpc (devnet-smoke-gate-rpc-body post-response))
             (post-chain-id (fixture-object-field post-rpc "result"))
             (summary-json
               (ethereum-lisp.cli::devnet-node-summary-json-object node))
             (telemetry-fields
               (ethereum-lisp.cli::devnet-node-telemetry-fields node))
             (reported-origins
               (cdr (assoc "publicCorsOrigins"
                           summary-json
                           :test #'string=)))
             (telemetry-origins
               (cdr (assoc "publicCorsOrigins"
                           telemetry-fields
                           :test #'string=))))
        (devnet-smoke-gate-require
         (= 204 (devnet-cli-http-status preflight-response))
         "Public CORS preflight status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status post-response))
         "Public CORS JSON-RPC status mismatch")
        (devnet-smoke-gate-require
         (= 403 (devnet-cli-http-status blocked-response))
         "Public CORS blocked-origin status mismatch")
        (devnet-smoke-gate-require
         (string= "https://runner.example"
                  (devnet-smoke-gate-http-header
                   preflight-response
                   "Access-Control-Allow-Origin"))
         "Public CORS preflight origin header mismatch")
        (devnet-smoke-gate-require
         (string= "GET, POST, OPTIONS"
                  (devnet-smoke-gate-http-header
                   preflight-response
                   "Access-Control-Allow-Methods"))
         "Public CORS preflight methods header mismatch")
        (devnet-smoke-gate-require
         (string= "Authorization, Content-Type"
                  (devnet-smoke-gate-http-header
                   preflight-response
                   "Access-Control-Allow-Headers"))
         "Public CORS preflight allowed-headers mismatch")
        (devnet-smoke-gate-require
         (string= "https://observer.example"
                  (devnet-smoke-gate-http-header
                   post-response
                   "Access-Control-Allow-Origin"))
         "Public CORS JSON-RPC origin header mismatch")
        (devnet-smoke-gate-require
         (string= "Origin"
                  (devnet-smoke-gate-http-header post-response "Vary"))
         "Public CORS JSON-RPC Vary header mismatch")
        (devnet-smoke-gate-require
         (string= "0x539" post-chain-id)
         "Public CORS JSON-RPC chain id mismatch")
        (devnet-smoke-gate-require
         (= 0 (getf summary :engine-connections))
         "Public CORS Engine connection count mismatch")
        (devnet-smoke-gate-require
         (= +devnet-smoke-gate-public-cors-connections+
            (getf summary :public-connections))
         "Public CORS public connection count mismatch")
        (devnet-smoke-gate-require
         (equal *devnet-smoke-gate-public-cors-origins* reported-origins)
         "Public CORS summary origins mismatch")
        (devnet-smoke-gate-require
         (string= "https://runner.example,https://observer.example"
                  telemetry-origins)
         "Public CORS telemetry origins mismatch")
        (list :origins (copy-list *devnet-smoke-gate-public-cors-origins*)
              :reported-origins reported-origins
              :telemetry-origins telemetry-origins
              :preflight-status (devnet-cli-http-status preflight-response)
              :post-status (devnet-cli-http-status post-response)
              :blocked-status (devnet-cli-http-status blocked-response)
              :engine-connections (getf summary :engine-connections)
              :public-connections (getf summary :public-connections)
              :total-connections (getf summary :total-connections)))))
  #-sbcl
  (error "Public CORS smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-engine-cors ()
  #+sbcl
  (let ((jwt-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-smoke-engine-cors-jwt"
           "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path
                     (namestring
                      (devnet-smoke-gate-reference-path
                       +devnet-cli-genesis-fixture+))
                     :port 8551
                     :public-port 8545
                     :jwt-secret-path (namestring jwt-path)
                     :engine-cors-origins
                     *devnet-smoke-gate-engine-cors-origins*))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (engine-body
                    (devnet-smoke-gate-json-rpc-request
                     451
                     "engine_getClientVersionV1"
                     (list
                      (list (cons "code" "TT")
                            (cons "name" "test")
                            (cons "version" "1.1.1")
                            (cons "commit" "0x12345678")))))
                  (preflight-output (make-string-output-stream))
                  (post-output (make-string-output-stream))
                  (blocked-output (make-string-output-stream))
                  (engine-served-count 0)
                  (engine-done-p nil)
                  (engine-requests
                    (list
                     (cons
                      (devnet-smoke-gate-http-request
                       "OPTIONS" "/" :origin
                       "https://engine-runner.example")
                      preflight-output)
                     (cons
                      (devnet-cli-json-rpc-http-request
                       engine-body
                       :token token
                       :origin "https://engine-observer.example")
                      post-output)
                     (cons
                      (devnet-smoke-gate-http-request
                       "OPTIONS" "/" :origin
                       "https://blocked-engine.example")
                      blocked-output)))
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "engine-cors-engine"
                      :accept-function
                      (lambda ()
                        (when engine-requests
                          (destructuring-bind (request . output)
                              (pop engine-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream request)
                             :output-stream output
                             :close-function
                             (lambda ()
                               (incf engine-served-count)
                               (when (= engine-served-count
                                        +devnet-smoke-gate-engine-cors-connections+)
                                 (setf engine-done-p t)))))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "engine-cors-public"
                      :accept-function
                      (lambda ()
                        (loop until engine-done-p
                              do (sleep 0.001))
                        nil)
                      :close-function (lambda () nil))
                     :max-connections
                     +devnet-smoke-gate-engine-cors-connections+))
                  (preflight-response
                    (get-output-stream-string preflight-output))
                  (post-response
                    (get-output-stream-string post-output))
                  (blocked-response
                    (get-output-stream-string blocked-output))
                  (post-rpc
                    (devnet-smoke-gate-rpc-body post-response))
                  (post-result
                    (first (fixture-object-field post-rpc "result")))
                  (summary-json
                    (ethereum-lisp.cli::devnet-node-summary-json-object
                     node))
                  (telemetry-fields
                    (ethereum-lisp.cli::devnet-node-telemetry-fields node))
                  (reported-origins
                    (cdr (assoc "engineCorsOrigins"
                                summary-json
                                :test #'string=)))
                  (telemetry-origins
                    (cdr (assoc "engineCorsOrigins"
                                telemetry-fields
                                :test #'string=))))
             (devnet-smoke-gate-require
              (= 204 (devnet-cli-http-status preflight-response))
              "Engine CORS preflight status mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status post-response))
              "Engine CORS JSON-RPC status mismatch")
             (devnet-smoke-gate-require
              (= 403 (devnet-cli-http-status blocked-response))
              "Engine CORS blocked-origin status mismatch")
             (devnet-smoke-gate-require
              (string= "https://engine-runner.example"
                       (devnet-smoke-gate-http-header
                        preflight-response
                        "Access-Control-Allow-Origin"))
              "Engine CORS preflight origin header mismatch")
             (devnet-smoke-gate-require
              (string= "GET, POST, OPTIONS"
                       (devnet-smoke-gate-http-header
                        preflight-response
                        "Access-Control-Allow-Methods"))
              "Engine CORS preflight methods header mismatch")
             (devnet-smoke-gate-require
              (string= "Authorization, Content-Type"
                       (devnet-smoke-gate-http-header
                        preflight-response
                        "Access-Control-Allow-Headers"))
              "Engine CORS preflight allowed-headers mismatch")
             (devnet-smoke-gate-require
              (string= "https://engine-observer.example"
                       (devnet-smoke-gate-http-header
                        post-response
                        "Access-Control-Allow-Origin"))
              "Engine CORS JSON-RPC origin header mismatch")
             (devnet-smoke-gate-require
              (string= "Origin"
                       (devnet-smoke-gate-http-header post-response "Vary"))
              "Engine CORS JSON-RPC Vary header mismatch")
             (devnet-smoke-gate-require
              (string= "ethereum-lisp"
                       (fixture-object-field post-result "name"))
              "Engine CORS JSON-RPC client version mismatch")
             (devnet-smoke-gate-require
              (= +devnet-smoke-gate-engine-cors-connections+
                 (getf summary :engine-connections))
              "Engine CORS Engine connection count mismatch")
             (devnet-smoke-gate-require
              (= 0 (getf summary :public-connections))
              "Engine CORS public connection count mismatch")
             (devnet-smoke-gate-require
              (equal *devnet-smoke-gate-engine-cors-origins*
                     reported-origins)
              "Engine CORS summary origins mismatch")
             (devnet-smoke-gate-require
              (string= "https://engine-runner.example,https://engine-observer.example"
                       telemetry-origins)
              "Engine CORS telemetry origins mismatch")
             (list :origins
                   (copy-list *devnet-smoke-gate-engine-cors-origins*)
                   :reported-origins reported-origins
                   :telemetry-origins telemetry-origins
                   :preflight-status
                   (devnet-cli-http-status preflight-response)
                   :post-status (devnet-cli-http-status post-response)
                   :blocked-status
                   (devnet-cli-http-status blocked-response)
                   :engine-connections
                   (getf summary :engine-connections)
                   :public-connections
                   (getf summary :public-connections)
                   :total-connections
                   (getf summary :total-connections))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))))
  #-sbcl
  (error "Engine CORS smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-http-shaping ()
  #+sbcl
  (let ((jwt-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-smoke-http-shaping-jwt"
           "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path
                     (namestring
                      (devnet-smoke-gate-reference-path
                       +devnet-cli-genesis-fixture+))
                     :port 8551
                     :public-port 8545
                     :jwt-secret-path (namestring jwt-path)))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (engine-body
                    (devnet-smoke-gate-json-rpc-request
                     461
                     "engine_getClientVersionV1"
                     (list
                      (list (cons "code" "TT")
                            (cons "name" "test")
                            (cons "version" "1.1.1")
                            (cons "commit" "0x12345678")))))
                  (public-body
                    (devnet-smoke-gate-json-rpc-request
                     462 "eth_chainId" '()))
                  (engine-method-output (make-string-output-stream))
                  (engine-content-type-output (make-string-output-stream))
                  (public-method-output (make-string-output-stream))
                  (public-content-type-output (make-string-output-stream))
                  (engine-served-count 0)
                  (engine-done-p nil)
                  (engine-requests
                    (list
                     (cons
                      (devnet-smoke-gate-http-request
                       "PUT" "/"
                       :content-type "application/json"
                       :authorization (format nil "Bearer ~A" token)
                       :body engine-body)
                      engine-method-output)
                     (cons
                      (devnet-smoke-gate-http-request
                       "POST" "/"
                       :content-type "text/plain"
                       :authorization (format nil "Bearer ~A" token)
                       :body engine-body)
                      engine-content-type-output)))
                  (public-requests
                    (list
                     (cons
                      (devnet-smoke-gate-http-request
                       "PUT" "/"
                       :content-type "application/json"
                       :body public-body)
                      public-method-output)
                     (cons
                      (devnet-smoke-gate-http-request
                       "POST" "/"
                       :content-type "text/plain"
                       :body public-body)
                      public-content-type-output)))
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "http-shaping-engine"
                      :accept-function
                      (lambda ()
                        (when engine-requests
                          (destructuring-bind (request . output)
                              (pop engine-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream request)
                             :output-stream output
                             :close-function
                             (lambda ()
                               (incf engine-served-count)
                               (when (= engine-served-count
                                        +devnet-smoke-gate-http-shaping-engine-connections+)
                                 (setf engine-done-p t)))))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "http-shaping-public"
                      :accept-function
                      (lambda ()
                        (loop until engine-done-p
                              do (sleep 0.001))
                        (when public-requests
                          (destructuring-bind (request . output)
                              (pop public-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream request)
                             :output-stream output
                             :close-function (lambda () nil)))))
                      :close-function (lambda () nil))
                     :max-connections
                     +devnet-smoke-gate-http-shaping-public-connections+))
                  (engine-method-response
                    (get-output-stream-string engine-method-output))
                  (engine-content-type-response
                    (get-output-stream-string engine-content-type-output))
                  (public-method-response
                    (get-output-stream-string public-method-output))
                  (public-content-type-response
                    (get-output-stream-string public-content-type-output)))
             (devnet-smoke-gate-require
              (= 405 (devnet-cli-http-status engine-method-response))
              "Engine HTTP method rejection status mismatch")
             (devnet-smoke-gate-require
              (search "method not allowed"
                      (devnet-cli-http-body engine-method-response))
              "Engine HTTP method rejection body mismatch")
             (devnet-smoke-gate-require
              (= 415 (devnet-cli-http-status engine-content-type-response))
              "Engine HTTP content-type rejection status mismatch")
             (devnet-smoke-gate-require
              (search "invalid content type"
                      (devnet-cli-http-body engine-content-type-response))
              "Engine HTTP content-type rejection body mismatch")
             (devnet-smoke-gate-require
              (= 405 (devnet-cli-http-status public-method-response))
              "Public HTTP method rejection status mismatch")
             (devnet-smoke-gate-require
              (search "method not allowed"
                      (devnet-cli-http-body public-method-response))
              "Public HTTP method rejection body mismatch")
             (devnet-smoke-gate-require
              (= 415 (devnet-cli-http-status public-content-type-response))
              "Public HTTP content-type rejection status mismatch")
             (devnet-smoke-gate-require
              (search "invalid content type"
                      (devnet-cli-http-body public-content-type-response))
              "Public HTTP content-type rejection body mismatch")
             (devnet-smoke-gate-require
              (= +devnet-smoke-gate-http-shaping-engine-connections+
                 (getf summary :engine-connections))
              "HTTP shaping Engine connection count mismatch")
             (devnet-smoke-gate-require
              (= +devnet-smoke-gate-http-shaping-public-connections+
                 (getf summary :public-connections))
              "HTTP shaping public connection count mismatch")
             (list :engine-method-status
                   (devnet-cli-http-status engine-method-response)
                   :engine-content-type-status
                   (devnet-cli-http-status engine-content-type-response)
                   :public-method-status
                   (devnet-cli-http-status public-method-response)
                   :public-content-type-status
                   (devnet-cli-http-status public-content-type-response)
                   :engine-connections
                   (getf summary :engine-connections)
                   :public-connections
                   (getf summary :public-connections)
                   :total-connections
                   (getf summary :total-connections))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))))
  #-sbcl
  (error "HTTP shaping smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-vhosts ()
  #+sbcl
  (let* ((node
           (ethereum-lisp.cli:make-devnet-node
            :genesis-path
            (namestring
             (devnet-smoke-gate-reference-path
              +devnet-cli-genesis-fixture+))
            :port 8551
            :public-port 8545
            :engine-vhosts *devnet-smoke-gate-engine-vhosts*
            :public-vhosts *devnet-smoke-gate-public-vhosts*))
         (engine-output (make-string-output-stream))
         (blocked-engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (blocked-public-output (make-string-output-stream))
         (engine-requests
           (list
            (cons
             (devnet-smoke-gate-http-request
              "POST" "/"
              :host "engine.runner"
              :content-type "application/json"
              :body (devnet-smoke-gate-json-rpc-request
                     501 "engine_getClientVersionV1"
                     (list
                      (list (cons "code" "TT")
                            (cons "name" "test")
                            (cons "version" "1.1.1")
                            (cons "commit" "0x12345678")))))
             engine-output)
            (cons
             (devnet-smoke-gate-http-request
              "POST" "/"
              :host "blocked.engine"
              :content-type "application/json"
              :body (devnet-smoke-gate-json-rpc-request
                     502 "engine_getClientVersionV1" (list '())))
             blocked-engine-output)))
         (public-requests
           (list
            (cons
             (devnet-smoke-gate-http-request
              "POST" "/"
              :host "public.runner"
              :content-type "application/json"
              :body (devnet-smoke-gate-json-rpc-request
                     503 "eth_chainId" '()))
             public-output)
            (cons
             (devnet-smoke-gate-http-request
              "POST" "/"
              :host "blocked.public"
              :content-type "application/json"
              :body (devnet-smoke-gate-json-rpc-request
                     504 "eth_chainId" '()))
             blocked-public-output))))
    (dolist (request engine-requests)
      (destructuring-bind (request-string . output) request
        (engine-rpc-http-service-handle-stream
         (ethereum-lisp.cli:devnet-node-service node)
         (make-string-input-stream request-string)
         output)))
    (dolist (request public-requests)
      (destructuring-bind (request-string . output) request
        (engine-rpc-http-service-handle-stream
         (ethereum-lisp.cli:devnet-node-public-service node)
         (make-string-input-stream request-string)
         output)))
    (let ((engine-connection-count
            +devnet-smoke-gate-vhost-engine-connections+)
          (public-connection-count
            +devnet-smoke-gate-vhost-public-connections+))
      (let* ((engine-response (get-output-stream-string engine-output))
             (blocked-engine-response
               (get-output-stream-string blocked-engine-output))
             (public-response (get-output-stream-string public-output))
             (blocked-public-response
               (get-output-stream-string blocked-public-output))
             (summary-json
               (ethereum-lisp.cli::devnet-node-summary-json-object node))
             (telemetry-fields
               (ethereum-lisp.cli::devnet-node-telemetry-fields node))
             (reported-engine-vhosts
               (cdr (assoc "engineVhosts" summary-json :test #'string=)))
             (reported-public-vhosts
               (cdr (assoc "publicVhosts" summary-json :test #'string=)))
             (telemetry-engine-vhosts
               (cdr (assoc "engineVhosts" telemetry-fields :test #'string=)))
             (telemetry-public-vhosts
               (cdr (assoc "publicVhosts" telemetry-fields :test #'string=))))
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status engine-response))
         "Engine vhost allowed status mismatch")
        (devnet-smoke-gate-require
         (= 403 (devnet-cli-http-status blocked-engine-response))
         "Engine vhost blocked status mismatch")
        (devnet-smoke-gate-require
         (= 200 (devnet-cli-http-status public-response))
         "Public vhost allowed status mismatch")
        (devnet-smoke-gate-require
         (= 403 (devnet-cli-http-status blocked-public-response))
         "Public vhost blocked status mismatch")
        (devnet-smoke-gate-require
         (= +devnet-smoke-gate-vhost-engine-connections+
            engine-connection-count)
         "Vhost Engine connection count mismatch")
        (devnet-smoke-gate-require
         (= +devnet-smoke-gate-vhost-public-connections+
            public-connection-count)
         "Vhost public connection count mismatch")
        (devnet-smoke-gate-require
         (equal *devnet-smoke-gate-engine-vhosts* reported-engine-vhosts)
         "Vhost Engine summary mismatch")
        (devnet-smoke-gate-require
         (equal *devnet-smoke-gate-public-vhosts* reported-public-vhosts)
         "Vhost public summary mismatch")
        (devnet-smoke-gate-require
         (string= "engine.runner,localhost" telemetry-engine-vhosts)
         "Vhost Engine telemetry mismatch")
        (devnet-smoke-gate-require
         (string= "public.runner,localhost" telemetry-public-vhosts)
         "Vhost public telemetry mismatch")
        (list :engine-vhosts
              (copy-list *devnet-smoke-gate-engine-vhosts*)
              :public-vhosts
              (copy-list *devnet-smoke-gate-public-vhosts*)
              :reported-engine-vhosts reported-engine-vhosts
              :reported-public-vhosts reported-public-vhosts
              :telemetry-engine-vhosts telemetry-engine-vhosts
              :telemetry-public-vhosts telemetry-public-vhosts
              :engine-allowed-status
              (devnet-cli-http-status engine-response)
              :engine-blocked-status
              (devnet-cli-http-status blocked-engine-response)
              :public-allowed-status
              (devnet-cli-http-status public-response)
              :public-blocked-status
              (devnet-cli-http-status blocked-public-response)
              :engine-connections engine-connection-count
              :public-connections public-connection-count
              :total-connections
              (+ engine-connection-count public-connection-count)))))
  #-sbcl
  (error "Vhost smoke verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-rpc-prefixes ()
  #+sbcl
  (let ((jwt-path
          (devnet-cli-temp-path
           "ethereum-lisp-devnet-smoke-rpc-prefix-jwt"
           "hex")))
    (unwind-protect
         (progn
           (devnet-cli-write-temp-file jwt-path +devnet-cli-jwt-secret+)
           (let* ((node
                    (ethereum-lisp.cli:make-devnet-node
                     :genesis-path
                     (namestring
                      (devnet-smoke-gate-reference-path
                       +devnet-cli-genesis-fixture+))
                     :port 8551
                     :public-port 8545
                     :jwt-secret-path (namestring jwt-path)
                     :engine-rpc-prefix
                     +devnet-smoke-gate-engine-rpc-prefix+
                     :public-rpc-prefix
                     +devnet-smoke-gate-public-rpc-prefix+))
                  (secret (hex-to-bytes +devnet-cli-jwt-secret+))
                  (token (engine-rpc-make-jwt-token secret 0))
                  (engine-body
                    (devnet-smoke-gate-json-rpc-request
                     601
                     "engine_getClientVersionV1"
                     (list
                      (list (cons "code" "TT")
                            (cons "name" "test")
                            (cons "version" "1.1.1")
                            (cons "commit" "0x12345678")))))
                  (public-body
                    (devnet-smoke-gate-json-rpc-request
                     602 "eth_chainId" '()))
                  (engine-output (make-string-output-stream))
                  (blocked-engine-output (make-string-output-stream))
                  (public-output (make-string-output-stream))
                  (blocked-public-output (make-string-output-stream))
                  (engine-served-count 0)
                  (public-served-count 0)
                  (engine-done-p nil)
                  (engine-requests
                    (list
                     (cons
                      (devnet-cli-json-rpc-http-request
                       engine-body
                       :token token
                       :target
                       +devnet-smoke-gate-engine-rpc-prefix+)
                      engine-output)
                     (cons
                      (devnet-cli-json-rpc-http-request
                       engine-body
                       :token token
                       :target "/")
                      blocked-engine-output)))
                  (public-requests
                    (list
                     (cons
                      (devnet-cli-json-rpc-http-request
                       public-body
                       :target
                       +devnet-smoke-gate-public-rpc-prefix+)
                      public-output)
                     (cons
                      (devnet-cli-json-rpc-http-request
                       public-body
                       :target "/")
                      blocked-public-output)))
                  (summary
                    (ethereum-lisp.cli:start-devnet-node-listeners
                     node
                     (make-engine-rpc-http-listener
                      :endpoint "rpc-prefix-engine"
                      :accept-function
                      (lambda ()
                        (when engine-requests
                          (destructuring-bind (request . output)
                              (pop engine-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream request)
                             :output-stream output
                             :close-function
                             (lambda ()
                               (incf engine-served-count)
                               (when (= engine-served-count
                                        +devnet-smoke-gate-rpc-prefix-engine-connections+)
                                 (setf engine-done-p t)))))))
                      :close-function (lambda () nil))
                     (make-engine-rpc-http-listener
                      :endpoint "rpc-prefix-public"
                      :accept-function
                      (lambda ()
                        (loop until engine-done-p
                              do (sleep 0.001))
                        (when public-requests
                          (destructuring-bind (request . output)
                              (pop public-requests)
                            (make-engine-rpc-http-connection
                             :input-stream
                             (make-string-input-stream request)
                             :output-stream output
                             :close-function
                             (lambda () (incf public-served-count))))))
                      :close-function (lambda () nil))
                     :max-connections
                     +devnet-smoke-gate-rpc-prefix-engine-connections+))
                  (engine-response
                    (get-output-stream-string engine-output))
                  (blocked-engine-response
                    (get-output-stream-string blocked-engine-output))
                  (public-response
                    (get-output-stream-string public-output))
                  (blocked-public-response
                    (get-output-stream-string blocked-public-output))
                  (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
                  (public-rpc (devnet-smoke-gate-rpc-body public-response))
                  (summary-json
                    (ethereum-lisp.cli::devnet-node-summary-json-object
                     node))
                  (telemetry-fields
                    (ethereum-lisp.cli::devnet-node-telemetry-fields node))
                  (reported-engine-prefix
                    (cdr (assoc "engineRpcPrefix"
                                summary-json
                                :test #'string=)))
                  (reported-public-prefix
                    (cdr (assoc "publicRpcPrefix"
                                summary-json
                                :test #'string=)))
                  (telemetry-engine-prefix
                    (cdr (assoc "engineRpcPrefix"
                                telemetry-fields
                                :test #'string=)))
                  (telemetry-public-prefix
                    (cdr (assoc "publicRpcPrefix"
                                telemetry-fields
                                :test #'string=))))
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status engine-response))
              "Engine RPC prefix status mismatch")
             (devnet-smoke-gate-require
              (= 404 (devnet-cli-http-status blocked-engine-response))
              "Engine RPC blocked-prefix status mismatch")
             (devnet-smoke-gate-require
              (= 200 (devnet-cli-http-status public-response))
              "Public RPC prefix status mismatch")
             (devnet-smoke-gate-require
              (= 404 (devnet-cli-http-status blocked-public-response))
              "Public RPC blocked-prefix status mismatch")
             (devnet-smoke-gate-require
              (= +devnet-smoke-gate-rpc-prefix-engine-connections+
                 (getf summary :engine-connections))
              "RPC prefix Engine connection count mismatch")
             (devnet-smoke-gate-require
              (= +devnet-smoke-gate-rpc-prefix-public-connections+
                 (getf summary :public-connections))
              "RPC prefix public connection count mismatch")
             (devnet-smoke-gate-require
              (= engine-served-count
                 (getf summary :engine-connections))
              "RPC prefix served Engine count mismatch")
             (devnet-smoke-gate-require
              (= public-served-count
                 (getf summary :public-connections))
              "RPC prefix served public count mismatch")
             (devnet-smoke-gate-require
              (string= "ethereum-lisp"
                       (fixture-object-field
                        (first (fixture-object-field engine-rpc "result"))
                        "name"))
              "Engine RPC prefix client-version result mismatch")
             (devnet-smoke-gate-require
              (string= "0x539" (fixture-object-field public-rpc "result"))
              "Public RPC prefix chain id mismatch")
             (devnet-smoke-gate-require
              (string= +devnet-smoke-gate-engine-rpc-prefix+
                       reported-engine-prefix)
              "Engine RPC prefix summary mismatch")
             (devnet-smoke-gate-require
              (string= +devnet-smoke-gate-public-rpc-prefix+
                       reported-public-prefix)
              "Public RPC prefix summary mismatch")
             (devnet-smoke-gate-require
              (string= +devnet-smoke-gate-engine-rpc-prefix+
                       telemetry-engine-prefix)
              "Engine RPC prefix telemetry mismatch")
             (devnet-smoke-gate-require
              (string= +devnet-smoke-gate-public-rpc-prefix+
                       telemetry-public-prefix)
              "Public RPC prefix telemetry mismatch")
             (list :engine-prefix +devnet-smoke-gate-engine-rpc-prefix+
                   :public-prefix +devnet-smoke-gate-public-rpc-prefix+
                   :reported-engine-prefix reported-engine-prefix
                   :reported-public-prefix reported-public-prefix
                   :telemetry-engine-prefix telemetry-engine-prefix
                   :telemetry-public-prefix telemetry-public-prefix
                   :engine-status (devnet-cli-http-status engine-response)
                   :engine-blocked-status
                   (devnet-cli-http-status blocked-engine-response)
                   :public-status (devnet-cli-http-status public-response)
                   :public-blocked-status
                   (devnet-cli-http-status blocked-public-response)
                   :engine-connections (getf summary :engine-connections)
                   :public-connections (getf summary :public-connections)
                   :total-connections
                   (getf summary :total-connections))))
      (when (probe-file jwt-path)
        (delete-file jwt-path))))
  #-sbcl
  (error "RPC prefix smoke verification requires SBCL threads"))
