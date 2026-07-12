(in-package #:ethereum-lisp.test)

(defun devnet-smoke-gate-verify-restored-engine-rpc
    (node payload-id expected-parent-hash expected-block-number
     expected-head-block-number)
  #+sbcl
  (let* ((engine-output (make-string-output-stream))
         (public-output (make-string-output-stream))
         (engine-served-count 0)
         (public-served-count 0)
         (engine-done-p nil)
         (engine-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 170)
                  (cons "method" "engine_getPayloadV2")
                  (cons "params" (list payload-id)))))
         (public-request
           (json-encode
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 171)
                  (cons "method" "eth_blockNumber")
                  (cons "params" #()))))
         (summary
           (ethereum-lisp.cli:start-devnet-node-listeners
            node
            (make-engine-rpc-http-listener
             :endpoint "restored-engine-prepared-payload"
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
             :endpoint "restored-public-prepared-payload"
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
         (payload
           (fixture-object-field
            (fixture-object-field engine-rpc "result")
            "executionPayload")))
    (devnet-smoke-gate-require
     (= 1 (getf summary :engine-connections))
     "Restored Engine prepared-payload probe expected 1 Engine connection, got ~S"
     (getf summary :engine-connections))
    (devnet-smoke-gate-require
     (= 1 (getf summary :public-connections))
     "Restored Engine prepared-payload probe expected 1 public connection, got ~S"
     (getf summary :public-connections))
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status engine-response))
     "Restored engine_getPayloadV2 HTTP status mismatch")
    (devnet-smoke-gate-require
     (= 200 (devnet-cli-http-status public-response))
     "Restored prepared-payload eth_blockNumber HTTP status mismatch")
    (devnet-smoke-gate-require
     (not (fixture-object-field engine-rpc "error"))
     "Restored engine_getPayloadV2 returned an error")
    (devnet-smoke-gate-require
     (string= (hash32-to-hex expected-parent-hash)
              (fixture-object-field payload "parentHash"))
     "Restored prepared payload parent hash mismatch")
    (devnet-smoke-gate-require
     (string= expected-block-number
              (fixture-object-field payload "blockNumber"))
     "Restored prepared payload block number mismatch")
    (devnet-smoke-gate-require
     (string= expected-head-block-number
              (fixture-object-field public-rpc "result"))
     "Restored prepared-payload public block number mismatch")
    (list :prepared-payload-id payload-id
          :prepared-payload-parent-hash
          (fixture-object-field payload "parentHash")
          :prepared-payload-block-number
          (fixture-object-field payload "blockNumber")
          :engine-connections engine-served-count
          :public-connections public-served-count))
  #-sbcl
  (declare (ignore node payload-id expected-parent-hash expected-block-number
                   expected-head-block-number))
  #-sbcl
  (error "Restored devnet Engine RPC verification requires SBCL threads"))

