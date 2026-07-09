(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-verify-restored-remote-block-rpc
    (node remote-payload expected-block-hash expected-head-block-number)
  #+sbcl
  (let* ((engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (engine-served-count 0)
         (public-served-count 0)
         (engine-done-p nil)
         (engine-request
           (json-encode
            (engine-fixture-payload-request 172 remote-payload)))
         (public-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 173)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-remote-block"
             :accept-function
             (lambda ()
               (unless engine-done-p
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream
                   (devnet-cli-json-rpc-http-request engine-request))
                  :output-stream engine-output
                  :close-function
                  (lambda ()
                    (incf engine-served-count)
                    (setf engine-done-p t)))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-remote-block"
             :accept-function
             (lambda ()
               (loop until engine-done-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream
                 (devnet-cli-json-rpc-http-request public-request))
                :output-stream public-output
                :close-function
                (lambda () (incf public-served-count))))
             :close-function (lambda () nil))
            :max-connections 1))
         (engine-response (get-output-stream-string engine-output))
         (public-response (get-output-stream-string public-output))
         (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
         (public-rpc (devnet-smoke-gate-rpc-body public-response))
         (payload-status (fixture-object-field engine-rpc "result")))
    (devnet-smoke-gate-require
     (= 1 (getf summary :engine-connections))
     "Restored remote-block probe expected 1 Engine connection, got ~S"
     (getf summary :engine-connections))
    (devnet-smoke-gate-require
     (= 1 (getf summary :public-connections))
     "Restored remote-block probe expected 1 public connection, got ~S"
     (getf summary :public-connections))
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status engine-response))
     "Restored remote-block engine_newPayloadV2 HTTP status mismatch")
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status public-response))
     "Restored remote-block eth_blockNumber HTTP status mismatch")
    (devnet-smoke-gate-require
     (not (fixture-object-field engine-rpc "error"))
     "Restored remote-block engine_newPayloadV2 returned an error")
    (devnet-smoke-gate-require
     (string= +payload-status-syncing+
              (fixture-object-field payload-status "status"))
     "Restored remote-block engine_newPayloadV2 status mismatch")
    (devnet-smoke-gate-require
     (null (fixture-object-field payload-status "latestValidHash"))
     "Restored remote-block SYNCING status should not report latestValidHash")
    (devnet-smoke-gate-require
     (string= expected-head-block-number
              (fixture-object-field public-rpc "result"))
     "Restored remote-block public block number mismatch")
    (list :remote-block-hash (hash32-to-hex expected-block-hash)
          :remote-block-status (fixture-object-field payload-status "status")
          :engine-connections engine-served-count
          :public-connections public-served-count))
  #-sbcl
  (declare (ignore node remote-payload expected-block-hash
                   expected-head-block-number))
  #-sbcl
  (error "Restored devnet remote-block Engine RPC verification requires SBCL threads"))

(defun devnet-smoke-gate-verify-restored-invalid-tipset-rpc
    (node descendant-payload expected-latest-valid-hash
     expected-head-block-number)
  #+sbcl
  (let* ((engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (engine-served-count 0)
         (public-served-count 0)
         (engine-done-p nil)
         (engine-request
           (json-encode
            (engine-fixture-payload-request 174 descendant-payload)))
         (public-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 175)
                  (cons "method" "eth_blockNumber")
                  (cons "params" '()))))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-invalid-tipset"
             :accept-function
             (lambda ()
               (unless engine-done-p
                 (make-engine-rpc-http-connection
                  :input-stream
                  (make-string-input-stream
                   (devnet-cli-json-rpc-http-request engine-request))
                  :output-stream engine-output
                  :close-function
                  (lambda ()
                    (incf engine-served-count)
                    (setf engine-done-p t)))))
             :close-function (lambda () nil))
            (make-engine-rpc-http-listener
             :endpoint "restored-public-invalid-tipset"
             :accept-function
             (lambda ()
               (loop until engine-done-p
                     do (sleep 0.001))
               (make-engine-rpc-http-connection
                :input-stream
                (make-string-input-stream
                 (devnet-cli-json-rpc-http-request public-request))
                :output-stream public-output
                :close-function
                (lambda () (incf public-served-count))))
             :close-function (lambda () nil))
            :max-connections 1))
         (engine-response (get-output-stream-string engine-output))
         (public-response (get-output-stream-string public-output))
         (engine-rpc (devnet-smoke-gate-rpc-body engine-response))
         (public-rpc (devnet-smoke-gate-rpc-body public-response))
         (payload-status (fixture-object-field engine-rpc "result"))
         (validation-error
           (fixture-object-field payload-status "validationError")))
    (devnet-smoke-gate-require
     (= 1 (getf summary :engine-connections))
     "Restored invalid-tipset probe expected 1 Engine connection, got ~S"
     (getf summary :engine-connections))
    (devnet-smoke-gate-require
     (= 1 (getf summary :public-connections))
     "Restored invalid-tipset probe expected 1 public connection, got ~S"
     (getf summary :public-connections))
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status engine-response))
     "Restored invalid-tipset engine_newPayloadV2 HTTP status mismatch")
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status public-response))
     "Restored invalid-tipset eth_blockNumber HTTP status mismatch")
    (devnet-smoke-gate-require
     (not (fixture-object-field engine-rpc "error"))
     "Restored invalid-tipset engine_newPayloadV2 returned an error")
    (devnet-smoke-gate-require
     (string= +payload-status-invalid+
              (fixture-object-field payload-status "status"))
     "Restored invalid-tipset engine_newPayloadV2 status mismatch")
    (devnet-smoke-gate-require
     (string= (hash32-to-hex expected-latest-valid-hash)
              (fixture-object-field payload-status "latestValidHash"))
     "Restored invalid-tipset latestValidHash mismatch")
    (devnet-smoke-gate-require
     (string= "links to previously rejected block" validation-error)
     "Restored invalid-tipset validation error mismatch: ~A"
     validation-error)
    (devnet-smoke-gate-require
     (string= expected-head-block-number
              (fixture-object-field public-rpc "result"))
     "Restored invalid-tipset public block number mismatch")
    (list :invalid-tipset-status
          (fixture-object-field payload-status "status")
          :invalid-tipset-validation-error validation-error
          :engine-connections engine-served-count
          :public-connections public-served-count))
  #-sbcl
  (declare (ignore node descendant-payload expected-latest-valid-hash
                   expected-head-block-number))
  #-sbcl
  (error "Restored devnet invalid-tipset Engine RPC verification requires SBCL threads"))

