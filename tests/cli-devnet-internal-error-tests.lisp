(in-package #:ethereum-lisp.test)

;;;; A block whose execution failed internally: how often it is tried again,
;;;; and where the failure is logged.
;;;;
;;;; A BLOCK-EXECUTION-INTERNAL-ERROR is a defect in this node, not a verdict
;;;; (docs/evidence/sec5-evm-edge-audit.txt). The sync coordinator contains it
;;;; and executes the block again later; these tests pin how much later, and
;;;; that every ingress that executes a block logs the failure. The record is
;;;; docs/evidence/sec5-robustness-followups.txt.

(deftest devnet-execution-retry-wait-doubles-to-its-cap-and-ends-for-a-new-target
  (:layer :unit :module :p2p)
  (is (equal '(2 4 8 16 32 64 128 256 300 300)
             (loop for failures from 1 to 10
                   collect (ethereum-lisp.cli::devnet-execution-retry-delay-seconds
                            failures))))
  (let* ((table (make-hash-table :test #'equal))
         (hash (make-hash32 (make-byte-vector 32 :initial-element 7)))
         (target (make-hash32 (make-byte-vector 32 :initial-element 8)))
         (other-target (make-hash32 (make-byte-vector 32 :initial-element 9)))
         (entry (ethereum-lisp.cli::devnet-execution-retry-note-failure
                 table hash 12 target 100)))
    (is (= 1 (ethereum-lisp.cli::devnet-execution-retry-failures entry)))
    (is (= 102 (ethereum-lisp.cli::devnet-execution-retry-next-at entry)))
    ;; The wait holds for the target it was seen under, until it ends.
    (is (eq entry (ethereum-lisp.cli::devnet-execution-retry-waiting
                   table target 101)))
    (is (null (ethereum-lisp.cli::devnet-execution-retry-waiting
               table target 102)))
    ;; A new target, or none, retries at once.
    (is (null (ethereum-lisp.cli::devnet-execution-retry-waiting
               table other-target 101)))
    (is (null (ethereum-lisp.cli::devnet-execution-retry-waiting
               table nil 101)))
    ;; A failure under the new target keeps doubling: it is the same block.
    (ethereum-lisp.cli::devnet-execution-retry-note-failure
     table hash 12 other-target 102)
    (is (= 2 (ethereum-lisp.cli::devnet-execution-retry-failures entry)))
    (is (= 100 (ethereum-lisp.cli::devnet-execution-retry-first-at entry)))
    (is (= 102 (ethereum-lisp.cli::devnet-execution-retry-last-at entry)))
    (is (= 106 (ethereum-lisp.cli::devnet-execution-retry-next-at entry)))
    (is (eq entry (ethereum-lisp.cli::devnet-execution-retry-waiting
                   table other-target 105)))
    (is (null (ethereum-lisp.cli::devnet-execution-retry-waiting
               table target 105)))
    ;; Only execution clears the entry, and with it the count.
    (is (null (ethereum-lisp.cli::devnet-execution-retry-remove-executed
               table (constantly nil))))
    (is (= 1 (hash-table-count table)))
    (is (equal (list entry)
               (ethereum-lisp.cli::devnet-execution-retry-remove-executed
                table (lambda (seen) (hash32= seen hash)))))
    (is (zerop (hash-table-count table))))
  ;; The table is bounded: the entry that failed longest ago leaves first.
  (let ((table (make-hash-table :test #'equal)))
    (loop for index from 1 to ethereum-lisp.cli::+devnet-execution-retry-max-entries+
          do (ethereum-lisp.cli::devnet-execution-retry-note-failure
              table (make-hash32 (make-byte-vector 32 :initial-element index))
              index nil (+ 1000 index)))
    (ethereum-lisp.cli::devnet-execution-retry-note-failure
     table (make-hash32 (make-byte-vector 32 :initial-element 200)) 200 nil 5000)
    (is (= ethereum-lisp.cli::+devnet-execution-retry-max-entries+
           (hash-table-count table)))
    (is (null (gethash (hash32-to-hex
                        (make-hash32 (make-byte-vector 32 :initial-element 1)))
                       table)))
    (is (gethash (hash32-to-hex
                  (make-hash32 (make-byte-vector 32 :initial-element 2)))
                 table))))

(defun internal-error-log-field (event name)
  (second (member name (rest event) :test #'equal)))

(deftest devnet-sync-coordinator-waits-before-executing-a-failed-block-again
  (:layer :unit :module :p2p)
  ;; sec5-evm-edge-audit.txt, Not verified: a persistent internal failure was
  ;; retried on every coordinator pass -- every second and on every peer
  ;; announcement -- re-downloading and re-executing the block with an :error
  ;; line each time. RED at c677bdf0: the second, immediate pass ran the sync
  ;; work again.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0 :public-port 0))
         (config (ethereum-lisp.cli::devnet-node-config node))
         (block (first (eth-sync-produce-empty-blocks
                        (ethereum-lisp.cli::devnet-node-genesis-block node)
                        config 1)))
         (hash (block-hash block))
         (first-target (make-hash32 (make-byte-vector 32 :initial-element 3)))
         (second-target (make-hash32 (make-byte-vector 32 :initial-element 4)))
         (target (list first-target))
         (failing-p t)
         (calls 0)
         (logs '()))
    (flet ((pass (&rest arguments)
             (apply #'ethereum-lisp.cli::devnet-node-sync-coordinator-pass
                    node arguments))
           (events (name)
             (reverse (remove name logs :key #'first :test-not #'string=))))
      (devnet-peer-sync-call-with-function-overrides
       (list
        (cons 'ethereum-lisp.cli::devnet-node-multi-sync-pass
              (lambda (seen-node)
                (declare (ignore seen-node))
                (incf calls)
                (if failing-p
                    (error 'block-execution-internal-error
                           :block-number 1 :block-hash hash
                           :cause (make-condition
                                   'type-error :datum (expt 2 256)
                                   :expected-type
                                   '(mod 4611686018427387901)))
                    1)))
        (cons 'ethereum-lisp.cli::devnet-node-forkchoice-sync-targets
              (lambda (seen-node)
                (declare (ignore seen-node))
                (list (car target))))
        (cons 'ethereum-lisp.cli::devnet-peer-manager-log
              (lambda (seen-node name &rest fields)
                (declare (ignore seen-node))
                (push (cons name fields) logs))))
       (lambda ()
         ;; Two passes back to back, on the wall clock: the second waits.
         (is (null (pass)))
         (is (= 1 calls))
         (is (null (pass)))
         (is (= 1 calls))
         ;; On a controlled clock from here on. The first failure's two
         ;; seconds are over by now + 2, the second failure's four at + 6.
         (let ((now (+ (unix-time) 2)))
           (is (null (pass :now now)))
           (is (= 2 calls))
           (is (null (pass :now (+ now 3))))
           (is (= 2 calls))
           (is (null (pass :now (+ now 4))))
           (is (= 3 calls))
           ;; A new CL target is tried at once, and the doubling goes on.
           (setf (car target) second-target)
           (is (null (pass :now (+ now 5))))
           (is (= 4 calls))
           (is (null (pass :now (+ now 6))))
           (is (= 4 calls))
           ;; Every attempt was logged with the running count.
           (let ((failures (events "peer.sync.execution_internal_error")))
             (is (= 4 (length failures)))
             (is (equal '(1 2 3 4)
                        (mapcar (lambda (event)
                                  (internal-error-log-field event "failures"))
                                failures)))
             (is (equal '(2 4 8 16)
                        (mapcar (lambda (event)
                                  (internal-error-log-field
                                   event "retryInSeconds"))
                                failures)))
             (is (eql (internal-error-log-field (first failures) "firstAt")
                      (internal-error-log-field (fourth failures) "firstAt")))
             (is (eql (+ now 5)
                      (internal-error-log-field (fourth failures) "lastAt"))))
           ;; The block executes (Engine newPayload, say): the entry goes, the
           ;; recovery is logged, and the sync runs on the very next pass.
           (setf failing-p nil)
           (ethereum-lisp.cli::devnet-peer-sync-import-block node block)
           (is (chain-store-state-available-p
                (ethereum-lisp.cli::devnet-node-store node) hash))
           (is (eql 1 (pass :now (+ now 7))))
           (is (= 5 calls))
           (let ((recovered (events "peer.sync.execution_recovered")))
             (is (= 1 (length recovered)))
             (is (eql 4 (internal-error-log-field (first recovered) "failures")))
             ;; Three passes waited: the immediate one, + 3 and + 6.
             (is (eql 3 (internal-error-log-field (first recovered)
                                                 "deferredPasses"))))
           (is (zerop (hash-table-count
                       (ethereum-lisp.cli::devnet-node-execution-retries
                        node))))))))))

(defun internal-error-engine-request (node method params)
  "Answer one Engine request through NODE's own Engine service context, and
return the response object."
  (ethereum-lisp.rpc:rpc-handle-request
   (list (cons "jsonrpc" "2.0")
         (cons "id" 1)
         (cons "method" method)
         (cons "params" params))
   (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
    (ethereum-lisp.cli::devnet-node-service node))))

(defun internal-error-field (object name)
  (cdr (assoc name object :test #'string=)))

(deftest devnet-engine-prepared-payload-internal-error-is-logged
  (:layer :unit :module :engine)
  ;; A newPayload of the block this node itself built publishes the build's
  ;; retained post-state instead of executing (the prepared-payload
  ;; shortcut). An internal failure there already answered -32603 and cached
  ;; nothing, but no line was logged: the node's logging executor never ran.
  ;; RED at c677bdf0: no engine.execution.internal_error event.
  (let* ((sink (ethereum-lisp.telemetry:make-memory-telemetry-sink))
         (sender (address-to-hex (fixture-private-key-address 1)))
         (funded "0x0000000000000000000000000000000000001001")
         (genesis-json
           ;; The Paris genesis, funding the sender of the one transaction
           ;; below: a pre-Cancun build keeps its post-state (the shortcut's
           ;; subject) only when it executes something.
           (let ((at (search funded *eth-sync-paris-genesis-json*)))
             (concatenate 'string
                          (subseq *eth-sync-paris-genesis-json* 0 at)
                          sender
                          (subseq *eth-sync-paris-genesis-json*
                                  (+ at (length funded))))))
         (node (ethereum-lisp.cli:make-devnet-node
                :genesis-json genesis-json
                :port 0 :public-port 0 :telemetry-sink sink))
         (genesis (ethereum-lisp.cli::devnet-node-genesis-block node))
         (admitted
           (ethereum-lisp.rpc:rpc-handle-request
            (list (cons "jsonrpc" "2.0")
                  (cons "id" 1)
                  (cons "method" "eth_sendRawTransaction")
                  (cons "params"
                        (list
                         (bytes-to-hex
                          (transaction-encoding
                           (fixture-sign-legacy-transaction
                            (make-legacy-transaction
                             :nonce 1 :gas-price 2000000000 :gas-limit 21000
                             :to (make-address
                                  (make-byte-vector 20 :initial-element 7))
                             :value 1)
                            1 1337))))))
            (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
             (ethereum-lisp.cli::devnet-node-public-service node))))
         (prepared
           (internal-error-engine-request
            node "engine_forkchoiceUpdatedV1"
            (list (list (cons "headBlockHash"
                              (hash32-to-hex (block-hash genesis)))
                        (cons "safeBlockHash"
                              (hash32-to-hex (zero-hash32)))
                        (cons "finalizedBlockHash"
                              (hash32-to-hex (zero-hash32))))
                  (list (cons "timestamp"
                              (format nil "0x~X"
                                      (+ 12 (block-header-timestamp
                                             (block-header genesis)))))
                        (cons "prevRandao" (hash32-to-hex (zero-hash32)))
                        (cons "suggestedFeeRecipient"
                              (address-to-hex (zero-address)))))))
         (payload-id
           (internal-error-field (internal-error-field prepared "result")
                                 "payloadId"))
         (payload
           (internal-error-field
            (internal-error-engine-request
             node "engine_getPayloadV1" (list payload-id))
            "result"))
         (executions 0))
    (is (stringp (internal-error-field admitted "result")))
    (is (stringp payload-id))
    (is (= 1 (length (internal-error-field payload "transactions"))))
    (let* ((original
             (fdefinition
              'ethereum-lisp.execution-service:execute-and-commit-engine-payload))
           (response
             (devnet-peer-sync-call-with-function-overrides
              (list
               ;; Counts executions: the shortcut must not execute.
               (cons 'ethereum-lisp.execution-service:execute-and-commit-engine-payload
                     (lambda (&rest arguments)
                       (incf executions)
                       (apply original arguments)))
               ;; The shortcut's publication of the retained post-state.
               (cons 'ethereum-lisp.execution-service:execute-and-commit-block
                     (lambda (&rest arguments)
                       (declare (ignore arguments))
                       (error 'type-error :datum (expt 2 256)
                                          :expected-type
                                          '(mod 4611686018427387901)))))
              (lambda ()
                (internal-error-engine-request
                 node "engine_newPayloadV1" (list payload))))))
      (is (= 0 executions))
      (is (null (internal-error-field response "result")))
      (is (eql -32603 (internal-error-field
                       (internal-error-field response "error") "code")))
      (let ((events (snap-tail-internal-error-events sink)))
        (is (= 1 (length events)))
        (is (eq :error (ethereum-lisp.telemetry:telemetry-event-value
                        (first events))))
        (is (equal "engine" (snap-tail-event-field (first events) "source")))
        (is (equal "1" (snap-tail-event-field (first events) "block")))
        (is (search "4611686018427387901"
                    (snap-tail-event-field (first events) "error")))))
    ;; No verdict was cached: the retry publishes the build and is VALID.
    (is (string= +payload-status-valid+
                 (internal-error-field
                  (internal-error-field
                   (internal-error-engine-request
                    node "engine_newPayloadV1" (list payload))
                   "result")
                  "status")))))
