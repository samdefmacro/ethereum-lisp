(in-package #:ethereum-lisp.test)

(deftest rpc-http-package-boundary
  (let ((http (find-package '#:ethereum-lisp.rpc-http))
        (rpc (find-package '#:ethereum-lisp.rpc))
        (execution (find-package '#:ethereum-lisp.execution))
        (core (find-package '#:ethereum-lisp.core)))
    (is (not (member core (package-use-list http))))
    (is (member rpc (package-use-list http)))
    (is (not (member execution (package-use-list http))))
    (dolist (name '("RPC-HTTP-HANDLE-REQUEST"
                    "RPC-HTTP-HANDLE-STREAM"
                    "MAKE-ENGINE-RPC-HTTP-SERVICE"
                    "ENGINE-RPC-HTTP-SERVICE-RPC-CONTEXT"))
      (multiple-value-bind (symbol status)
          (find-symbol name http)
        (is symbol)
        (is (eq :external status))))
    (dolist (name '("MAKE-ENGINE-RPC-HTTP-SERVICE"
                    "ENGINE-RPC-HANDLE-HTTP-REQUEST-STRING"
                    "ENGINE-RPC-HANDLE-HTTP-STREAM"))
      (multiple-value-bind (http-symbol http-status)
          (find-symbol name http)
        (multiple-value-bind (core-symbol core-status)
            (find-symbol name core)
          (is (eq :external http-status))
          (is (eq :external core-status))
          (is (eq http-symbol core-symbol)))))
    (multiple-value-bind (symbol status)
        (find-symbol "ENGINE-RPC-HANDLE-PUBLIC-METHOD" http)
      (is (null symbol))
      (is (null status)))))

(deftest rpc-http-service-owns-rpc-context
  (let* ((service (make-engine-rpc-http-service))
         (context
           (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
            service)))
    (is (typep context 'ethereum-lisp.rpc:rpc-context))
    (is (eq (engine-rpc-http-service-store service)
            (ethereum-lisp.rpc:rpc-context-store context)))
    (is (eq (engine-rpc-http-service-config service)
            (ethereum-lisp.rpc:rpc-context-config context)))))

(deftest engine-rpc-http-post-dispatches-json-rpc
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12))))
    (let* ((body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":17,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json; charset=utf-8~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (http-response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (rpc-response (parse-json (http-body http-response)))
           (local (first (field rpc-response "result"))))
      (is (= 200 (http-status http-response)))
      (is (search "Connection: close" http-response))
      (is (= 17 (field rpc-response "id")))
      (is (string= "ethereum-lisp" (field local "name"))))
    (let* ((body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":117,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST /engine/v1?trace=true HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (http-response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config)
              :rpc-prefix "/engine"))
           (rpc-response (parse-json (http-body http-response))))
      (is (= 200 (http-status http-response)))
      (is (= 117 (field rpc-response "id"))))
    (let* ((body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":30,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST /unexpected HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (http-response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 404 (http-status http-response)))
      (is (search "not found" (http-body http-response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST /public HTTP/1.1
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config)
              :rpc-prefix "/engine")))
      (is (= 404 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "OPTIONS / HTTP/1.1
Origin: https://runner.example
Access-Control-Request-Method: POST
Access-Control-Request-Headers: Content-Type, Authorization

"
              (make-engine-payload-memory-store)
              (make-chain-config)
              :cors-origins '("*"))))
      (is (= 204 (http-status response)))
      (is (search "Access-Control-Allow-Origin: *" response))
      (is (search "Access-Control-Allow-Methods: GET, POST, OPTIONS"
                  response))
      (is (search "Access-Control-Allow-Headers: Authorization, Content-Type"
                  response)))
    (let* ((body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":119,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Origin: https://runner.example~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config)
              :cors-origins '("https://runner.example"))))
      (is (= 200 (http-status response)))
      (is (search "Access-Control-Allow-Origin: https://runner.example"
                  response))
      (is (search "Vary: Origin" response)))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "OPTIONS / HTTP/1.1
Origin: https://other.example
Access-Control-Request-Method: POST

"
              (make-engine-payload-memory-store)
              (make-chain-config)
              :cors-origins '("https://runner.example"))))
      (is (= 403 (http-status response))))
    (let* ((body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":120,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST / HTTP/1.1~%Host: runner.local:8551~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config)
              :allowed-hosts '("runner.local")))
           (rpc-response (parse-json (http-body response))))
      (is (= 200 (http-status response)))
      (is (= 120 (field rpc-response "id"))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Host: blocked.local
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config)
              :allowed-hosts '("runner.local"))))
      (is (= 403 (http-status response)))
      (is (search "host is not allowed" response)))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config)
              :allowed-hosts '("*"))))
      (is (= 200 (http-status response))))
    (let* ((body "{\"jsonrpc\":\"2.0\",\"id\":18,")
           (request
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body))
           (http-response
             (engine-rpc-handle-http-request-string
              request
              (make-engine-payload-memory-store)
              (make-chain-config)))
           (rpc-response (parse-json (http-body http-response)))
           (error (field rpc-response "error")))
      (is (= 200 (http-status http-response)))
      (is (not (field rpc-response "id")))
      (is (= -32700 (field error "code"))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: text/plain

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 415 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "PUT / HTTP/1.1
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 405 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 2x

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: -1

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: +2

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 2
Content-Length: 2

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1
: nope
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.0
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))
    (let* ((response
             (engine-rpc-handle-http-request-string
              "POST / HTTP/1.1 trailing
Content-Type: application/json

{}"
              (make-engine-payload-memory-store)
              (make-chain-config))))
      (is (= 400 (http-status response))))))

(deftest engine-rpc-http-validates-jwt-bearer-auth
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12)))
           (request (body &key token)
             (with-output-to-string (stream)
               (format stream "POST / HTTP/1.1~%Host: localhost~%")
               (format stream "Content-Type: application/json~%")
               (when token
                 (format stream "Authorization: Bearer ~A~%" token))
               (format stream "Content-Length: ~D~%~%~A" (length body) body))))
    (let* ((secret (make-byte-vector 32 :initial-element #x42))
           (now 1000)
           (body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":18,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (token (engine-rpc-make-jwt-token secret now))
           (http-response
             (engine-rpc-handle-http-request-string
              (request body :token token)
              (make-engine-payload-memory-store)
              (make-chain-config)
              :jwt-secret secret
              :now now))
           (rpc-response (parse-json (http-body http-response)))
           (local (first (field rpc-response "result"))))
      (is (string=
           "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpYXQiOjEwMDB9.WR0G-_BFmXHetdB5_3grgcntOfG-gyUJd1ALOObOAbM"
           token))
      (is (= 200 (http-status http-response)))
      (is (= 18 (field rpc-response "id")))
      (is (string= "ethereum-lisp" (field local "name")))
      (let ((missing-response
              (engine-rpc-handle-http-request-string
               (request body)
               (make-engine-payload-memory-store)
               (make-chain-config)
               :jwt-secret secret
               :now now)))
        (is (= 401 (http-status missing-response))))
      (let* ((stale-token (engine-rpc-make-jwt-token secret (- now 61)))
             (stale-response
               (engine-rpc-handle-http-request-string
                (request body :token stale-token)
                (make-engine-payload-memory-store)
                (make-chain-config)
                :jwt-secret secret
                :now now)))
        (is (= 401 (http-status stale-response))))
      (let* ((expired-token
               (engine-rpc-make-jwt-token
                secret now :expires-at (1- now)))
             (expired-response
               (engine-rpc-handle-http-request-string
                (request body :token expired-token)
                (make-engine-payload-memory-store)
                (make-chain-config)
                :jwt-secret secret
                :now now)))
        (is (= 401 (http-status expired-response))))
      (let* ((duplicate-request
               (with-output-to-string (stream)
                 (format stream "POST / HTTP/1.1~%Host: localhost~%")
                 (format stream "Content-Type: application/json~%")
                 (format stream "Authorization: Bearer ~A~%" token)
                 (format stream "Authorization: Bearer ~A~%"
                         (engine-rpc-make-jwt-token secret (- now 61)))
                 (format stream "Content-Length: ~D~%~%~A"
                         (length body)
                         body)))
             (duplicate-response
               (engine-rpc-handle-http-request-string
                duplicate-request
                (make-engine-payload-memory-store)
                (make-chain-config)
                :jwt-secret secret
                :now now)))
        (is (= 401 (http-status duplicate-response)))))))

(deftest engine-rpc-http-stream-handles-single-connection
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12))))
    (let* ((secret (make-byte-vector 32 :initial-element #x24))
           (now 2000)
           (token (engine-rpc-make-jwt-token secret now))
           (body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":19,"
              "\"method\":\"engine_getClientVersionV1\","
              "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
              "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
           (request
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Authorization: Bearer ~A~%Content-Length: ~D~%~%~A"
                     token
                     (length body)
                     body))
           (input (make-string-input-stream request))
           (output (make-string-output-stream))
           (returned-response
             (engine-rpc-handle-http-stream
              input
              output
              (make-engine-payload-memory-store)
              (make-chain-config)
              :jwt-secret secret
              :now now))
           (written-response (get-output-stream-string output))
           (rpc-response (parse-json (http-body written-response)))
           (local (first (field rpc-response "result"))))
      (is (string= returned-response written-response))
      (is (= 200 (http-status written-response)))
      (is (search "Connection: close" written-response))
      (is (= 19 (field rpc-response "id")))
      (is (string= "ethereum-lisp" (field local "name"))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 4

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 2x

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: +2

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
Content-Type: application/json
Content-Length: 2
Content-Length: 2

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1
: nope
Content-Type: application/json

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.0
Content-Type: application/json

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))
    (let* ((input
             (make-string-input-stream
              "POST / HTTP/1.1 trailing
Content-Type: application/json

{}"))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input
       output
       (make-engine-payload-memory-store)
       (make-chain-config))
      (is (= 400 (http-status (get-output-stream-string output)))))))

(deftest engine-rpc-http-request-telemetry-includes-response-outcome
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (request (body)
             (format nil
                     "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                     (length body)
                     body)))
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (head-hash
             "0x1111111111111111111111111111111111111111111111111111111111111111")
           (zero-hash
             "0x0000000000000000000000000000000000000000000000000000000000000000")
           (body
             (concatenate
              'string
              "{\"jsonrpc\":\"2.0\",\"id\":30,"
              "\"method\":\"engine_forkchoiceUpdatedV1\","
              "\"params\":[{\"headBlockHash\":\"" head-hash "\","
              "\"safeBlockHash\":\"" zero-hash "\","
              "\"finalizedBlockHash\":\"" zero-hash "\"},null]}"))
           (input (make-string-input-stream (request body)))
           (output (make-string-output-stream))
           (response
             (engine-rpc-handle-http-stream
              input output
              (make-engine-payload-memory-store)
              (make-chain-config)
              :telemetry-sink sink))
           (rpc-response (parse-json (http-body response)))
           (fields
             (ethereum-lisp.telemetry:telemetry-event-fields
              (first (ethereum-lisp.telemetry:telemetry-events sink)))))
      (is (string= +payload-status-syncing+
                   (field (field (field rpc-response "result")
                                 "payloadStatus")
                          "status")))
      (is (string= "/" (field fields "httpTarget")))
      (is (string= +payload-status-syncing+
                   (field fields "rpcPayloadStatus"))))
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (body
             "{\"jsonrpc\":\"2.0\",\"id\":31,\"method\":\"engine_missingMethod\",\"params\":[]}")
           (input (make-string-input-stream (request body)))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input output
       (make-engine-payload-memory-store)
       (make-chain-config)
       :telemetry-sink sink)
      (let ((fields
              (ethereum-lisp.telemetry:telemetry-event-fields
               (first (ethereum-lisp.telemetry:telemetry-events sink)))))
        (is (string= "-32601" (field fields "rpcErrorCode")))))
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (body "{\"jsonrpc\":\"2.0\",\"id\":32,")
           (input (make-string-input-stream (request body)))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input output
       (make-engine-payload-memory-store)
       (make-chain-config)
       :telemetry-sink sink)
      (let ((fields
              (ethereum-lisp.telemetry:telemetry-event-fields
               (first (ethereum-lisp.telemetry:telemetry-events sink)))))
        (is (string= "200" (field fields "status")))
        (is (string= "-32700" (field fields "rpcErrorCode")))
        (is (null (field fields "rpcMethods")))))
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (body
             "{\"jsonrpc\":\"2.0\",\"id\":33,\"method\":\"eth_blockNumber\",\"params\":7}")
           (input (make-string-input-stream (request body)))
           (output (make-string-output-stream)))
      (engine-rpc-handle-http-stream
       input output
       (make-engine-payload-memory-store)
       (make-chain-config)
       :telemetry-sink sink)
      (let ((fields
              (ethereum-lisp.telemetry:telemetry-event-fields
               (first (ethereum-lisp.telemetry:telemetry-events sink)))))
        (is (string= "200" (field fields "status")))
        (is (string= "eth_blockNumber" (field fields "rpcMethods")))
        (is (string= "-32600" (field fields "rpcErrorCode")))))))

(deftest engine-rpc-http-service-wraps-stream-configuration
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12))))
    (let* ((coinbase
             (address-from-hex "0x00000000000000000000000000000000000000cb"))
           (default-service (make-engine-rpc-http-service))
           (secret (make-byte-vector 32 :initial-element #x55))
           (sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (now 3000)
           (service
             (make-engine-rpc-http-service
              :host "127.0.0.1"
              :port 8551
              :jwt-secret secret
              :now-provider (lambda () now)
              :import-function #'execute-and-commit-engine-payload
              :rpc-prefix "/engine"
              :coinbase coinbase
              :telemetry-sink sink)))
      (is (string= "localhost:8551"
                   (engine-rpc-http-service-endpoint default-service)))
      (is (string= "127.0.0.1:8551"
                   (engine-rpc-http-service-endpoint service)))
      (is (null (engine-rpc-http-service-telemetry-sink default-service)))
      (is (eq sink (engine-rpc-http-service-telemetry-sink service)))
      (is (null
           (engine-rpc-http-service-import-function default-service)))
      (is (string= "/" (engine-rpc-http-service-rpc-prefix default-service)))
      (is (string= "/engine" (engine-rpc-http-service-rpc-prefix service)))
      (is (string= (address-to-hex (zero-address))
                   (address-to-hex
                    (engine-rpc-http-service-coinbase default-service))))
      (is (string= (address-to-hex coinbase)
                   (address-to-hex
                    (engine-rpc-http-service-coinbase service))))
      (is (typep (engine-rpc-http-service-store service)
                 'engine-payload-memory-store))
      (is (typep (engine-rpc-http-service-config service) 'chain-config))
      (is (functionp (engine-rpc-http-service-import-function service)))
      (let* ((body
               (concatenate
                'string
                "{\"jsonrpc\":\"2.0\",\"id\":20,"
                "\"method\":\"engine_getClientVersionV1\","
                "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
                "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
             (token (engine-rpc-make-jwt-token secret now))
             (request
               (format nil
                       "POST /engine HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Authorization: Bearer ~A~%Content-Length: ~D~%~%~A"
                       token
                       (length body)
                       body))
             (input (make-string-input-stream request))
             (output (make-string-output-stream))
             (response
               (engine-rpc-http-service-handle-stream
                service input output))
             (rpc-response (parse-json (http-body response)))
             (local (first (field rpc-response "result"))))
        (is (= 200 (http-status response)))
        (is (string= response (get-output-stream-string output)))
        (is (= 20 (field rpc-response "id")))
        (is (string= "ethereum-lisp" (field local "name"))))
      (let ((events (ethereum-lisp.telemetry:telemetry-events sink)))
        (is (= 4 (length events)))
        (is (string= "engine.rpc.http.stream.start"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (first events))))
        (is (string= "engine.rpc.http.request"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (second events))))
        (is (string= "200"
                     (cdr (assoc "status"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (second events))
                                 :test #'string=))))
        (is (string= "engine_getClientVersionV1"
                     (cdr (assoc "rpcMethods"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (second events))
                                 :test #'string=))))
        (is (string= "engine.rpc.http.streams"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (third events))))
        (is (= 1
               (ethereum-lisp.telemetry:telemetry-event-value
                (third events))))
        (is (string= "engine.rpc.http.stream.finish"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (fourth events))))
        (is (string= "127.0.0.1:8551"
                     (cdr (assoc "endpoint"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (first events))
                                 :test #'string=)))))
      (signals block-validation-error
        (make-engine-rpc-http-service :rpc-prefix "engine"))
      (signals block-validation-error
        (make-engine-rpc-http-service :port 70000))
      (signals block-validation-error
        (make-engine-rpc-http-service
         :jwt-secret (make-byte-vector 31 :initial-element 1)))
      (signals block-validation-error
        (make-engine-rpc-http-service :import-function "not a function")))))

(deftest engine-rpc-http-service-serves-listener-connections
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12)))
           (request (id)
             (let ((body
                     (format nil
                             "{\"jsonrpc\":\"2.0\",\"id\":~D,\"method\":\"engine_getClientVersionV1\",\"params\":[{\"code\":\"TT\",\"name\":\"test\",\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"
                             id)))
               (format nil
                       "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                       (length body)
                       body))))
    (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
           (service (make-engine-rpc-http-service :telemetry-sink sink))
           (output-a (make-string-output-stream))
           (output-b (make-string-output-stream))
           (closed-connections 0)
           (closed-listener-p nil)
           (connections
             (list
              (make-engine-rpc-http-connection
               :input-stream (make-string-input-stream (request 21))
               :output-stream output-a
               :close-function (lambda () (incf closed-connections)))
              (make-engine-rpc-http-connection
               :input-stream (make-string-input-stream (request 22))
               :output-stream output-b
               :close-function (lambda () (incf closed-connections)))))
           (listener
             (make-engine-rpc-http-listener
              :endpoint (engine-rpc-http-service-endpoint service)
              :accept-function
              (lambda ()
                (when connections
                  (pop connections)))
              :close-function
              (lambda () (setf closed-listener-p t)))))
      (is (string= "localhost:8551"
                   (engine-rpc-http-listener-endpoint listener)))
      (is (= 2 (engine-rpc-http-service-serve-listener
                service listener :max-connections 10)))
      (is (= 2 closed-connections))
      (is closed-listener-p)
      (let* ((response-a (get-output-stream-string output-a))
             (response-b (get-output-stream-string output-b))
             (rpc-a (parse-json (http-body response-a)))
             (rpc-b (parse-json (http-body response-b))))
        (is (= 200 (http-status response-a)))
        (is (= 200 (http-status response-b)))
        (is (= 21 (field rpc-a "id")))
        (is (= 22 (field rpc-b "id"))))
      (let ((events (ethereum-lisp.telemetry:telemetry-events sink)))
        (is (= 11 (length events)))
        (is (string= "engine.rpc.http.listener.start"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (first events))))
        (is (string= "engine.rpc.http.stream.start"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (second events))))
        (is (string= "engine.rpc.http.request"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (third events))))
        (is (string= "200"
                     (cdr (assoc "status"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (third events))
                                 :test #'string=))))
        (is (string= "engine_getClientVersionV1"
                     (cdr (assoc "rpcMethods"
                                 (ethereum-lisp.telemetry:telemetry-event-fields
                                  (third events))
                                 :test #'string=))))
        (is (string= "engine.rpc.http.stream.finish"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (fifth events))))
        (is (string= "engine.rpc.http.listener.connections"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (tenth events))))
        (is (= 2
               (ethereum-lisp.telemetry:telemetry-event-value
                (tenth events))))
        (is (string= "engine.rpc.http.listener.finish"
                     (ethereum-lisp.telemetry:telemetry-event-name
                      (nth 10 events)))))
      (signals block-validation-error
        (engine-rpc-http-listener-accept
         (make-engine-rpc-http-listener
          :endpoint "localhost:8551"
          :accept-function (lambda () "not-a-connection"))))
      (signals block-validation-error
        (engine-rpc-http-service-serve-listener
         service listener :max-connections -1)))))

#+sbcl
(eval-when (:compile-toplevel :load-toplevel :execute)
  (require :sb-bsd-sockets))

#+sbcl
(deftest engine-rpc-http-service-serves-local-socket
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=)))
           (http-body (response)
             (let ((boundary (search (format nil "~C~C~C~C"
                                             #\Return #\Newline
                                             #\Return #\Newline)
                                     response)))
               (subseq response (+ boundary 4))))
           (http-status (response)
             (let* ((line-end (position #\Return response))
                    (status-line (subseq response 0 line-end)))
               (parse-integer status-line :start 9 :end 12)))
           (endpoint-port (endpoint)
             (parse-integer
              endpoint
              :start (1+ (position #\: endpoint :from-end t))))
           (read-stream-string (stream)
             (with-output-to-string (out)
               (loop for char = (read-char stream nil nil)
                     while char
                     do (write-char char out))))
           (connect-stream (host port)
             (let ((socket (make-instance 'sb-bsd-sockets:inet-socket
                                          :type :stream
                                          :protocol :tcp)))
               (sb-bsd-sockets:socket-connect
                socket
                (sb-bsd-sockets:make-inet-address host)
                port)
               (sb-bsd-sockets:socket-make-stream
                socket
                :input t
                :output t
                :element-type 'character
                :external-format :utf-8
                :buffering :none))))
    (let* ((service (make-engine-rpc-http-service
                     :host "127.0.0.1"
                     :port 0))
           (listener
             (handler-case
                 (make-engine-rpc-http-socket-listener service)
               (sb-bsd-sockets:operation-not-permitted-error ()
                 (skip-test
                  "Local socket bind is not permitted in this sandbox"))))
           (port (endpoint-port
                  (engine-rpc-http-listener-endpoint listener)))
           (server-thread
             (sb-thread:make-thread
              (lambda ()
                (engine-rpc-http-service-serve-listener
                 service listener :max-connections 1)))))
      (unwind-protect
           (let* ((body
                    (concatenate
                     'string
                     "{\"jsonrpc\":\"2.0\",\"id\":23,"
                     "\"method\":\"engine_getClientVersionV1\","
                     "\"params\":[{\"code\":\"TT\",\"name\":\"test\","
                     "\"version\":\"1.1.1\",\"commit\":\"0x12345678\"}]}"))
                  (request
                    (format nil
                            "POST / HTTP/1.1~%Host: localhost~%Content-Type: application/json~%Content-Length: ~D~%~%~A"
                            (length body)
                            body))
                  (stream (connect-stream "127.0.0.1" port)))
             (unwind-protect
                  (progn
                    (write-string request stream)
                    (finish-output stream)
                    (let* ((response (read-stream-string stream))
                           (rpc-response (parse-json (http-body response)))
                           (local (first (field rpc-response "result"))))
                      (is (= 200 (http-status response)))
                      (is (search "Connection: close" response))
                      (is (= 23 (field rpc-response "id")))
                      (is (string= "ethereum-lisp"
                                   (field local "name")))))
               (close stream))
             (sb-thread:join-thread server-thread))
        (ignore-errors (engine-rpc-http-listener-close listener))))))
