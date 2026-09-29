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

(defun debug-trace-test-node (sender-keys block-count)
  "A memory devnet node holding BLOCK-COUNT imported transfer blocks, each with
two transactions per key in SENDER-KEYS. Returns the node and the blocks."
  (let* ((genesis-json (devnet-np-latency-genesis-json sender-keys 8))
         (blocks (devnet-np-latency-build-blocks
                  genesis-json sender-keys 8 block-count))
         (node (ethereum-lisp.cli:make-devnet-node
                :genesis-json genesis-json :port 0)))
    (read-view-state-import node blocks)
    (values node blocks)))

(defun debug-trace-test-call (node method params)
  "METHOD with PARAMS through NODE's public RPC context, as a parsed object."
  (ethereum-lisp.rpc:rpc-handle-request
   (list (cons "jsonrpc" "2.0") (cons "id" 1)
         (cons "method" method) (cons "params" params))
   (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
    (ethereum-lisp.cli:devnet-node-public-service node))))

(deftest debug-trace-block-executes-each-transaction-once
  ;; RED on 3c0cfeab: debug_traceBlock* replayed every transaction's prefix
  ;; before tracing it, so a block of n transactions applied n(n-1)/2 of them
  ;; (6 here) and traced each through a separate call simulation. Now the
  ;; block runs once from its parent state, with a tracer attached per
  ;; transaction: APPLY-MESSAGE runs exactly n times.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (multiple-value-bind (node blocks) (debug-trace-test-node '(1 2) 2)
      (let* ((block (second blocks))
             (transactions (block-transactions block))
             (applied 0)
             (response nil))
        (is (= 4 (length transactions)))
        (sb-int:encapsulate 'ethereum-lisp.execution::apply-message
                            'debug-trace-count
                            (lambda (function &rest arguments)
                              (incf applied)
                              (apply function arguments)))
        (unwind-protect
             (setf response (debug-trace-test-call
                             node "debug_traceBlockByNumber" (list "0x2")))
          (sb-int:unencapsulate 'ethereum-lisp.execution::apply-message
                                'debug-trace-count))
        (is (null (field response "error")))
        (is (= (length transactions) applied))
        (let ((results (field response "result")))
          (is (= (length transactions) (length results)))
          (loop for entry in results
                for transaction in transactions
                do (is (equal (hash32-to-hex (transaction-hash transaction))
                              (field entry "txHash")))
                   (let ((frame (field entry "result")))
                     (is (equal "CALL" (field frame "type")))
                     (is (equal (address-to-hex (transaction-to transaction))
                                (field frame "to")))
                     ;; The top frame's gasUsed is the receipt's, as geth's
                     ;; callTracer reports it (OnTxEnd): 21,000 a transfer.
                     (is (equal "0x5208" (field frame "gasUsed")))
                     ;; A plain transfer returns nothing: no output key.
                     (is (null (assoc "output" frame :test #'string=)))))
          ;; debug_traceTransaction answers each one the same way.
          (loop for entry in results
                for transaction in transactions
                do (is (equal (field entry "result")
                              (field (debug-trace-test-call
                                      node "debug_traceTransaction"
                                      (list (hash32-to-hex
                                             (transaction-hash transaction))))
                                     "result")))))))))

(defun debug-trace-test-contract-code ()
  "CALLCODE, DELEGATECALL and STATICCALL to 0xbb, then CREATE and CREATE2 of an
initcode that deploys the one-byte code 0x2a, then STOP."
  (let ((callee "60bb612710")               ; PUSH1 0xbb PUSH2 10000
        (four-zeros "6000600060006000")     ; retSize retOffset argsSize argsOffset
        (initcode-in-memory                 ; PUSH10 <initcode> PUSH1 0 MSTORE
          "69602a60005360016000f3600052"))
    (hex-to-bytes
     (concatenate
      'string
      four-zeros "6000" callee "f2" "50"    ; CALLCODE value 0, POP
      four-zeros callee "f4" "50"           ; DELEGATECALL, POP
      four-zeros callee "fa" "50"           ; STATICCALL, POP
      initcode-in-memory
      "600a60166000f0" "50"                 ; CREATE size 10 offset 22 value 0
      "6001600a60166000f5" "50"             ; CREATE2 salt 1
      "00"))))

(deftest debug-trace-call-labels-every-call-and-create-frame
  ;; RED on 3c0cfeab: CALLCODE and DELEGATECALL frames were labelled CALL, the
  ;; DELEGATECALL frame named the contract's own caller as FROM, and CREATE and
  ;; CREATE2 made no frame at all. geth's callTracer (eth/tracers/native/
  ;; call.go and core/vm/evm.go at 38271784): the opcode is the type, the
  ;; executing contract is FROM for all four calls, DELEGATECALL carries the
  ;; frame's own value, STATICCALL no value, and a creation's output is the
  ;; code it deployed.
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config
                    :chain-id 1 :homestead-block 0 :eip150-block 0
                    :eip155-block 0 :eip158-block 0 :byzantium-block 0
                    :constantinople-block 0 :petersburg-block 0
                    :istanbul-block 0 :berlin-block 0 :london-block 0))
           (sender (address-from-hex
                    "0x00000000000000000000000000000000000000ee"))
           (contract (address-from-hex
                      "0x00000000000000000000000000000000000000aa"))
           (callee (address-from-hex
                    "0x00000000000000000000000000000000000000bb"))
           (state (make-state-db))
           (block (make-block
                   :header (make-block-header
                            :number 30 :timestamp 300 :gas-limit 10000000
                            :base-fee-per-gas 0))))
      (state-db-set-account state sender
                            (make-state-account :nonce 0 :balance 1000))
      (state-db-set-code state contract (debug-trace-test-contract-code))
      (state-db-set-code state callee (hex-to-bytes "00"))
      (setf (block-header-state-root (block-header block)) (state-db-root state))
      (chain-store-put-block store block :state-available-p t)
      (commit-state-db-to-chain-store store (block-hash block) state)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 1)
                      (cons "method" "debug_traceCall")
                      (cons "params"
                            (list (list (cons "from" (address-to-hex sender))
                                        (cons "to" (address-to-hex contract))
                                        (cons "value" "0x5")
                                        (cons "gas" "0x200000"))
                                  "latest")))
                store config
                :allowed-method-p #'engine-rpc-public-method-p))
             (result (field response "result"))
             (calls (field result "calls"))
             (contract-hex (address-to-hex contract))
             (callee-hex (address-to-hex callee)))
        (is (null (field response "error")))
        (is (equal '("CALLCODE" "DELEGATECALL" "STATICCALL" "CREATE" "CREATE2")
                   (mapcar (lambda (frame) (field frame "type")) calls)))
        (when (= 5 (length calls))
          (destructuring-bind (callcode delegatecall staticcall create create2)
              calls
            (dolist (frame calls)
              (is (equal contract-hex (field frame "from"))))
            (dolist (frame (list callcode delegatecall staticcall))
              (is (equal callee-hex (field frame "to"))))
            (is (equal "0x0" (field callcode "value")))
            ;; DELEGATECALL inherits the frame's value; STATICCALL has none.
            (is (equal "0x5" (field delegatecall "value")))
            (is (null (assoc "value" staticcall :test #'string=)))
            (dolist (frame (list create create2))
              (is (equal "0x2a" (field frame "output")))
              (is (equal "0x0" (field frame "value")))
              (is (equal "0x602a60005360016000f3" (field frame "input")))
              (is (stringp (field frame "to")))
              (is (not (equal contract-hex (field frame "to")))))
            (is (not (equal (field create "to") (field create2 "to"))))))))))

(deftest debug-trace-block-not-found-uses-server-error
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((response
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 3)
                    (cons "method" "debug_traceBlockByHash")
                    (cons "params"
                          (list
                           "0x0000000000000000000000000000000000000000000000000000000000000000")))
              (make-engine-payload-memory-store)
              (make-chain-config)
              :allowed-method-p #'engine-rpc-public-method-p))
           (error-object (field response "error")))
      (is (= -32000 (field error-object "code")))
      (is (search "not found" (field error-object "message"))))))

(deftest debug-trace-block-refuses-genesis-without-parent-state
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config))
           (genesis
             (make-block
              :header (make-block-header :number 0 :timestamp 1))))
      (chain-store-put-block store genesis :state-available-p t)
      (dolist (request
               (list
                (list "debug_traceBlockByHash"
                      (hash32-to-hex (block-hash genesis)))
                (list "debug_traceBlockByNumber" "0x0")))
        (let* ((response
                 (engine-rpc-handle-request
                  (list (cons "jsonrpc" "2.0")
                        (cons "id" 4)
                        (cons "method" (first request))
                        (cons "params" (list (second request))))
                  store config
                  :allowed-method-p #'engine-rpc-public-method-p))
               (error-object (field response "error")))
          (is (not (null error-object)))
          (when error-object
            (is (= -32000 (field error-object "code")))
            (is (string= "genesis is not traceable"
                         (field error-object "message")))))))))

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

(deftest parity-trace-namespace-is-explicitly-unavailable
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (is (not (engine-rpc-public-method-p "trace_replayTransaction")))
    (let* ((response
             (engine-rpc-handle-request
              (list (cons "jsonrpc" "2.0")
                    (cons "id" 8)
                    (cons "method" "trace_replayTransaction")
                    (cons "params" '()))
              (make-engine-payload-memory-store)
              (make-chain-config)
              :allowed-method-p #'engine-rpc-public-method-p))
           (error-object (field response "error")))
      (is (= -32601 (field error-object "code")))
      (is (search "not found" (field error-object "message"))))))

(deftest debug-set-head-rewinds-the-canonical-chain
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0
                                      :terminal-total-difficulty 100))
           ;; Proof-of-work blocks: a positive difficulty is what makes a
           ;; block pre-Merge under a TTD configuration.
           (genesis
             (make-block
              :header (make-block-header :number 0 :timestamp 1
                                         :difficulty #x20000)))
           (child
             (make-block
              :header
              (make-block-header
               :parent-hash (block-hash genesis)
               :number 1 :timestamp 2 :difficulty #x20000))))
      (chain-store-put-block store genesis :state-available-p t)
      (chain-store-put-block store child :state-available-p t)
      (chain-store-set-canonical-head
       store (block-hash child)
       :expected-chain-id 1 :chain-config config)
      (let ((response
              (engine-rpc-handle-request
               (list (cons "jsonrpc" "2.0")
                     (cons "id" 9)
                     (cons "method" "debug_setHead")
                     (cons "params" (list "0x0")))
               store config
               :allowed-method-p #'engine-rpc-public-method-p)))
        (is (null (field response "result")))
        (is (= 0 (chain-store-head-number store)))))))

(deftest debug-set-head-cannot-publish-a-post-merge-view
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           (config (make-chain-config :chain-id 1 :london-block 0))
           (genesis
             (make-block
              :header (make-block-header :number 0 :timestamp 1)))
           (child
             (make-block
              :header
              (make-block-header
               :parent-hash (block-hash genesis)
               :number 1 :timestamp 2))))
      (chain-store-put-block store genesis :state-available-p t)
      (chain-store-put-block store child :state-available-p t)
      (chain-store-set-canonical-head
       store (block-hash child)
       :expected-chain-id 1 :chain-config config)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 10)
                      (cons "method" "debug_setHead")
                      (cons "params" (list "0x0")))
                store config
                :allowed-method-p #'engine-rpc-public-method-p))
             (error-object (field response "error")))
        (is (= -32602 (field error-object "code")))
        (is (= 1 (chain-store-head-number store)))))))

(deftest debug-set-head-cannot-rewind-from-post-merge-to-pre-merge
  (labels ((field (object name)
             (cdr (assoc name object :test #'string=))))
    (let* ((store (make-engine-payload-memory-store))
           ;; Height zero is pre-Merge, while the current height one view is
           ;; explicitly post-Merge even though the positive TTD is not marked
           ;; globally passed.
           (config (make-chain-config :chain-id 1 :london-block 0
                                      :terminal-total-difficulty 100
                                      :merge-netsplit-block 1))
           (genesis
             (make-block
              :header (make-block-header :number 0 :timestamp 1)))
           (child
             (make-block
              :header
              (make-block-header
               :parent-hash (block-hash genesis)
               :number 1 :timestamp 2))))
      (chain-store-put-block store genesis :state-available-p t)
      (chain-store-put-block store child :state-available-p t)
      (chain-store-set-canonical-head
       store (block-hash child)
       :expected-chain-id 1 :chain-config config)
      (let* ((response
               (engine-rpc-handle-request
                (list (cons "jsonrpc" "2.0")
                      (cons "id" 11)
                      (cons "method" "debug_setHead")
                      (cons "params" (list "0x0")))
                store config
                :allowed-method-p #'engine-rpc-public-method-p))
             (error-object (field response "error")))
        (is (= -32602 (field error-object "code")))
        (is (= 1 (chain-store-head-number store)))
        (is (hash32= (block-hash child)
                     (chain-store-canonical-hash store 1)))))))
