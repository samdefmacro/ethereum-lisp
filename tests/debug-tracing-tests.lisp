(in-package #:ethereum-lisp.test)

;;;; debug_traceCall.
;;;;
;;;; The property worth testing is that the tree has the right SHAPE: a call
;;;; that makes a call produces a parent with a child, and the child reports
;;;; where it went and what it returned. Getting one frame back proves nothing,
;;;; since a tracer that only ever records the outermost call would also do that.

(deftest debug-trace-call-records-a-nested-call
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (caller
             (address-from-hex "0x00000000000000000000000000000000000000cc"))
           (callee
             (address-from-hex "0x00000000000000000000000000000000000000dd"))
           ;; CALL 0xdd with no value and no arguments, then STOP. The pushes
           ;; are in reverse stack order: retLength, retOffset, argsLength,
           ;; argsOffset, value, address, gas.
           (caller-code #(96 0 96 0 96 0 96 0 96 0 96 221 97 39 16 241 0))
           ;; MSTORE 7 at 0, RETURN mem[0:32].
           (callee-code #(96 7 96 0 82 96 32 96 0 243))
           (state (make-state-db))
           (block
             (make-block
              :header (make-block-header
                       :number 30
                       :timestamp 300
                       :gas-limit 1000000
                       :base-fee-per-gas 0
                       :state-root (state-db-root state)))))
      (state-db-set-code state caller caller-code)
      (state-db-set-code state callee callee-code)
      (setf (block-header-state-root (block-header block))
            (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 1)
                      (cons "method" "debug_traceCall")
                      (cons "params"
                            (list (list (cons "to" (address-to-hex caller))
                                        (cons "gas" "0x100000"))
                                  "latest")))
                store
                config
                :allowed-method-p #'engine-rpc-public-method-p))
             (result (field response "result")))
        (is (not (null result)))
        (is (null (field response "error")))
        ;; The outermost frame is the call we asked for.
        (is (equal "CALL" (field result "type")))
        (is (equal (address-to-hex caller) (field result "to")))
        ;; And it has the child it made. This is the assertion that a tracer
        ;; recording only the top frame would fail.
        (let ((calls (field result "calls")))
          (is (= 1 (length calls)))
          (let ((child (first calls)))
            (is (equal "CALL" (field child "type")))
            (is (equal (address-to-hex callee) (field child "to")))
            ;; The callee returned 32 bytes ending in 7.
            (is (equal (bytes-to-hex
                        (let ((bytes (make-byte-vector 32)))
                          (setf (aref bytes 31) 7)
                          bytes))
                       (field child "output")))
            ;; A successful frame carries no error key at all, rather than a
            ;; null one: a tool switching on presence would misread null.
            (is (null (assoc "error" child :test #'string=)))
            ;; A leaf carries no calls key either.
            (is (null (assoc "calls" child :test #'string=)))))))))

(deftest debug-trace-call-refuses-a-tracer-it-does-not-have
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (state (make-state-db))
           (block (make-block
                   :header (make-block-header
                            :number 1 :timestamp 10 :gas-limit 100000
                            :base-fee-per-gas 0
                            :state-root (state-db-root state)))))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      ;; structLog is a real geth tracer we do not have. Saying so is better
      ;; than accepting the parameter and quietly returning a call trace.
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 2)
                      (cons "method" "debug_traceCall")
                      (cons "params"
                            (list (list (cons "to" "0x00000000000000000000000000000000000000cc"))
                                  "latest"
                                  (list (cons "tracer" "structLog")))))
                store
                config
                :allowed-method-p #'engine-rpc-public-method-p))
             (error-object (field response "error")))
        (is (not (null error-object)))
        (is (= -32602 (field error-object "code")))
        (is (search "callTracer" (field error-object "message")))))))

(deftest evm-call-tracer-tree-is-well-formed
  ;; The tracer itself, with no EVM involved: entering and exiting frames must
  ;; nest, and a frame whose exit was skipped must not swallow its siblings.
  (let ((tracer (make-evm-call-tracer)))
    (let ((outer (evm-call-tracer-enter tracer :type "CALL" :gas 100)))
      (let ((inner (evm-call-tracer-enter tracer :type "STATICCALL" :gas 50)))
        (evm-call-tracer-exit tracer inner :gas-used 10))
      (let ((sibling (evm-call-tracer-enter tracer :type "CREATE" :gas 20)))
        (evm-call-tracer-exit tracer sibling :gas-used 5))
      (evm-call-tracer-exit tracer outer :gas-used 40))
    (let* ((root (evm-call-tracer-root tracer))
           (children (evm-call-frame-children root)))
      (is (equal "CALL" (evm-call-frame-type root)))
      (is (= 40 (evm-call-frame-gas-used root)))
      ;; Children come back in the order they ran, not the order they were
      ;; pushed.
      (is (= 2 (length children)))
      (is (equal "STATICCALL" (evm-call-frame-type (first children))))
      (is (equal "CREATE" (evm-call-frame-type (second children))))
      (is (null (evm-call-frame-children (first children)))))))
