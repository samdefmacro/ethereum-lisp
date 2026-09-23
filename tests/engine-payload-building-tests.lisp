(in-package #:ethereum-lisp.test)

;;;; Proposer-side payload building on a RocksDB-backed node: a txpool of a few
;;;; hundred signed transfers and contract calls, forkchoiceUpdated with payload
;;;; attributes, then getPayload at a chosen delay.  Every returned payload is
;;;; imported by a second, independent node through engine_newPayload, which is
;;;; the oracle that the built block is valid.

(defparameter *payload-building-contract*
  ;; phase-a-shanghai-genesis.json: code 0x6001600055 (SSTORE 1 at slot 0).
  "0x0000000000000000000000000000000000001002")

(defparameter *payload-building-request-contracts*
  '("0x00000961ef480eb55e80d19ad83579a64c007002"
    "0x0000bbddc7ce488642fb579f8b00f3a590007251"))

(defun payload-building-sender-keys (count)
  (loop for index from 0 below count collect (+ 5001 index)))

(defun payload-building-genesis-json (sender-keys)
  (devnet-cli-funded-txpool-genesis-json
   :private-keys sender-keys
   :config-fields (list (cons "cancunTime" "0x0")
                        (cons "pragueTime" "0x0")
                        (cons "osakaTime" "0x0"))
   :code-accounts
   (loop for address in *payload-building-request-contracts*
         collect (cons address #(#x60 #x00 #x60 #x00 #xf3)))))

(defun payload-building-transaction
    (config private-key nonce &key contract-call-p (tip 2)
                                   (max-fee 30000000000) (value 1))
  (eth-gossip-test-sign-dynamic-fee-transaction
   (make-dynamic-fee-transaction
    :chain-id (chain-config-chain-id config)
    :nonce nonce
    :max-priority-fee-per-gas tip
    :max-fee-per-gas max-fee
    :gas-limit (if contract-call-p 60000 21000)
    :to (address-from-hex
         (if contract-call-p
             *payload-building-contract*
             +devnet-cli-txpool-recipient+))
    :value value)
   private-key))

(defun payload-building-fill-pool
    (store config sender-keys per-sender &key poisoned-key)
  "Put PER-SENDER nonce-ordered transactions for each key into STORE's pending
pool; every fourth sender calls the storage contract instead of transferring.
With POISONED-KEY, that sender's first transaction moves more value than the
sender owns, so it is fee-eligible but fails execution."
  (let ((count 0))
    (loop for key in sender-keys
          for sender-index from 0
          do (dotimes (nonce per-sender)
               (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
                store
                (payload-building-transaction
                 config key nonce
                 :contract-call-p (zerop (mod sender-index 4))
                 :value (if (and (eql key poisoned-key) (zerop nonce))
                            (* 10 +devnet-cli-txpool-balance+)
                            1)))
               (incf count)))
    count))

(defun payload-building-request (id method params)
  (list (cons "jsonrpc" "2.0")
        (cons "id" id)
        (cons "method" method)
        (cons "params" params)))

(defun payload-building-field (object name)
  (cdr (assoc name object :test #'string=)))

(defun payload-building-forkchoice-state (head)
  (list (cons "headBlockHash" (hash32-to-hex head))
        (cons "safeBlockHash" (hash32-to-hex (zero-hash32)))
        (cons "finalizedBlockHash" (hash32-to-hex (zero-hash32)))))

(defparameter *payload-building-beacon-root*
  "0x3333333333333333333333333333333333333333333333333333333333333333")

(defun payload-building-attributes (timestamp)
  (list (cons "timestamp" (quantity-to-hex timestamp))
        (cons "prevRandao" (hash32-to-hex (zero-hash32)))
        (cons "suggestedFeeRecipient"
              "0x0000000000000000000000000000000000000c0b")
        (cons "withdrawals"
              (list (list (cons "index" "0x0")
                          (cons "validatorIndex" "0x1")
                          (cons "address"
                                "0x0000000000000000000000000000000000000d0d")
                          (cons "amount" "0x1"))))
        (cons "parentBeaconBlockRoot" *payload-building-beacon-root*)))

(defun payload-building-node-context (node)
  (ethereum-lisp.rpc-http::engine-rpc-http-service-rpc-context
   (ethereum-lisp.cli:devnet-node-service node)))

(defun payload-building-call (node request)
  "Send REQUEST through NODE's Engine context -- its priority store guard
included -- and return (VALUES RESPONSE MILLISECONDS)."
  (let ((started (get-internal-real-time)))
    (let ((response
            (ethereum-lisp.rpc::rpc-handle-request
             request (payload-building-node-context node))))
      (values response
              (round (* 1000 (- (get-internal-real-time) started))
                     internal-time-units-per-second)))))

(defun payload-building-import-verdict (verifier payload-object)
  "Import PAYLOAD-OBJECT (an executionPayload from getPayloadV5) into the
independent VERIFIER node via engine_newPayloadV4; return its status string."
  (let* ((json
           (format nil
                   "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"engine_newPayloadV4\",\"params\":[~A,[],\"~A\",[]]}"
                   (json-encode payload-object)
                   *payload-building-beacon-root*))
         (response
           (parse-json
            (engine-rpc-handle-request-json
             json
             (ethereum-lisp.cli:devnet-node-store verifier)
             (ethereum-lisp.cli:devnet-node-config verifier)))))
    (or (payload-building-field
         (payload-building-field response "result") "status")
        (format nil "error: ~A"
                (payload-building-field
                 (payload-building-field response "error") "message")))))

(defun payload-building-probe
    (node verifier timestamp delay-seconds &key concurrent-fcu-at)
  "fcU with attributes at TIMESTAMP, then getPayloadV5 after DELAY-SECONDS.
Returns a plist of latencies, the payload's transaction count and gas, and the
verifier's newPayload verdict.  With CONCURRENT-FCU-AT, a plain fcU (no
attributes) is timed that many seconds after the building fcU."
  (let* ((genesis (ethereum-lisp.cli::devnet-node-genesis-block node))
         (head (block-hash genesis))
         (fcu-ms nil)
         (plain-fcu-ms nil)
         (payload-id nil))
    (multiple-value-bind (response ms)
        (payload-building-call
         node
         (payload-building-request
          1 "engine_forkchoiceUpdatedV3"
          (list (payload-building-forkchoice-state head)
                (payload-building-attributes timestamp))))
      (setf fcu-ms ms
            payload-id (payload-building-field
                        (payload-building-field response "result")
                        "payloadId"))
      (unless payload-id
        (error "fcU did not return a payload id: ~S" response)))
    (let ((started (get-internal-real-time)))
      (flet ((sleep-until (seconds)
               (let ((remaining
                       (- seconds
                          (/ (- (get-internal-real-time) started)
                             internal-time-units-per-second))))
                 (when (plusp remaining)
                   (sleep remaining)))))
        (when concurrent-fcu-at
          (sleep-until concurrent-fcu-at)
          (multiple-value-bind (response ms)
              (payload-building-call
               node
               (payload-building-request
                2 "engine_forkchoiceUpdatedV3"
                (list (payload-building-forkchoice-state head))))
            (declare (ignore response))
            (setf plain-fcu-ms ms)))
        (sleep-until delay-seconds)
        (multiple-value-bind (response get-ms)
            (payload-building-call
             node
             (payload-building-request
              3 "engine_getPayloadV5" (list payload-id)))
          (let* ((envelope (payload-building-field response "result"))
                 (payload
                   (and envelope
                        (payload-building-field envelope "executionPayload"))))
            (unless payload
              (error "getPayload failed: ~S" response))
            (list :fcu-ms fcu-ms
                  :plain-fcu-ms plain-fcu-ms
                  :get-payload-ms get-ms
                  :transactions
                  (length (payload-building-field payload "transactions"))
                  :gas-used
                  (hex-to-quantity (payload-building-field payload "gasUsed"))
                  :verdict
                  (payload-building-import-verdict verifier payload))))))))

(defun call-with-payload-building-nodes
    (function &key (senders 40) (per-sender 8) poisoned-p
                   (improvement-thread-p t))
  "Call FUNCTION with a RocksDB-backed building node whose pool is filled, and
an independent in-memory verifier node on the same genesis."
  (let* ((keys (payload-building-sender-keys senders))
         (genesis-json (payload-building-genesis-json keys))
         (datadir (devnet-cli-temp-directory "ethereum-lisp-payload-building"))
         (database-path
           (ethereum-lisp.cli::devnet-cli-datadir-database-path
            datadir :rocksdb)))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-bls12381-backend
          (lambda ()
            (ethereum-lisp.cli::call-with-devnet-cli-kzg-verifier
             (lambda ()
               (payload-building-call-with-rocksdb-node
                genesis-json database-path keys per-sender poisoned-p
                improvement-thread-p function)))))
      (uiop:delete-directory-tree datadir
                                  :validate t
                                  :if-does-not-exist :ignore))))

(defun payload-building-call-with-rocksdb-node
    (genesis-json database-path keys per-sender poisoned-p
     improvement-thread-p function)
  (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (unwind-protect
                 (let* ((node
                          (ethereum-lisp.cli:make-devnet-node
                           :genesis-json genesis-json
                           :database-path database-path
                           :db-engine :rocksdb
                           :port 0 :public-port 0))
                        (verifier
                          (ethereum-lisp.cli:make-devnet-node
                           :genesis-json genesis-json
                           :port 0 :public-port 0))
                        (shutdown
                          (ethereum-lisp.cli:make-devnet-shutdown-controller))
                        (builder-error nil)
                        (thread nil))
                   (payload-building-fill-pool
                    (ethereum-lisp.cli:devnet-node-store node)
                    (ethereum-lisp.cli:devnet-node-config node)
                    keys per-sender
                    :poisoned-key (and poisoned-p (second keys)))
                   (unwind-protect
                        (progn
                          (when improvement-thread-p
                            (setf thread
                                  (ethereum-lisp.cli::devnet-start-payload-improvement-thread
                                   node shutdown
                                   (lambda (condition)
                                     (setf builder-error condition)))))
                          (multiple-value-prog1
                              (funcall function node verifier)
                            (when builder-error
                              (error "Payload builder failed: ~A"
                                     builder-error))))
                     (ethereum-lisp.cli:devnet-shutdown-request shutdown)
                     #+sbcl
                     (when thread
                       (sb-thread:join-thread thread :default nil))))
              (devnet-peer-sync-test-drop-cached-rocksdb-handle
               database-path)))))

(defun payload-building-measure
    (&key (delays '(0.5 1 2)) (senders 40) (per-sender 8)
          (poisoned-cases '(nil t)))
  "The measurement recorded in docs/evidence/sec5-payload-building.txt."
  (let ((results '()))
    (dolist (poisoned poisoned-cases)
      (call-with-payload-building-nodes
       (lambda (node verifier)
         (loop for delay in delays
               for timestamp from (if poisoned 20 10)
               do (push (list* :poisoned poisoned :delay delay
                               (payload-building-probe
                                node verifier timestamp delay
                                :concurrent-fcu-at 0.2))
                        results)))
       :senders senders :per-sender per-sender :poisoned-p poisoned))
    (nreverse results)))

(defun payload-building-measure-get-only
    (&key (delays '(0.5 1 2)) (senders 40) (per-sender 8) (poisoned-p t)
          (improvement-thread-p t))
  "getPayload latency with no other Engine request between fcU and getPayload."
  (let ((results '()))
    (call-with-payload-building-nodes
     (lambda (node verifier)
       (loop for delay in delays
             for timestamp from 30
             do (push (list* :poisoned poisoned-p :delay delay
                             (payload-building-probe
                              node verifier timestamp delay))
                      results)))
     :senders senders :per-sender per-sender :poisoned-p poisoned-p
     :improvement-thread-p improvement-thread-p)
    (nreverse results)))

(defun payload-building-attributes-struct (timestamp)
  (make-payload-attributes-v1
   :timestamp timestamp
   :prev-randao (zero-hash32)
   :suggested-fee-recipient (zero-address)
   :withdrawals '()
   :withdrawals-present-p t
   :parent-beacon-root (hash32-from-hex *payload-building-beacon-root*)
   :parent-beacon-root-present-p t))

(defun payload-building-open-payload (node timestamp)
  "fcU with attributes through NODE's Engine context; return the open payload."
  (let* ((genesis (ethereum-lisp.cli::devnet-node-genesis-block node))
         (response
           (payload-building-call
            node
            (payload-building-request
             1 "engine_forkchoiceUpdatedV3"
             (list (payload-building-forkchoice-state (block-hash genesis))
                   (payload-building-attributes timestamp)))))
         (payload-id
           (payload-building-field
            (payload-building-field response "result") "payloadId")))
    (is (stringp payload-id))
    (engine-payload-store-prepared-payload
     (ethereum-lisp.cli:devnet-node-store node)
     (hex-to-bytes payload-id)
     :copy-execution-state-p nil)))

(defun payload-building-stored (node prepared-payload)
  (engine-payload-store-prepared-payload
   (ethereum-lisp.cli:devnet-node-store node)
   (engine-prepared-payload-payload-id prepared-payload)
   :copy-execution-state-p nil))

(defun payload-building-transaction-count (prepared-payload)
  (length (block-transactions (engine-prepared-payload-block prepared-payload))))

(deftest engine-payload-build-executes-each-candidate-once
  (:layer :integration :module :engine)
  ;; Plan Section 6: each selected transaction executes at most once per
  ;; build.  One unexecutable transaction among 48 used to send the builder
  ;; into prefix re-execution, O(N^2) executions under the store guard (3.6 s
  ;; for 320 transactions on the d203fee6 dev image).
  (call-with-payload-building-nodes
   (lambda (node verifier)
     (let* ((store (ethereum-lisp.cli:devnet-node-store node))
            (config (ethereum-lisp.cli:devnet-node-config node))
            (genesis (ethereum-lisp.cli::devnet-node-genesis-block node))
            (attributes (payload-building-attributes-struct 11))
            (candidates
              (ethereum-lisp.engine-api:engine-rpc-pending-build-transactions
               store config (block-header genesis)))
            (original (fdefinition 'ethereum-lisp.execution::apply-message))
            (executions 0))
       (is (= 48 (length candidates)))
       (devnet-peer-sync-call-with-function-overrides
        (list (cons 'ethereum-lisp.execution::apply-message
                    (lambda (&rest arguments)
                      (incf executions)
                      (apply original arguments))))
        (lambda ()
          ;; RED control: the prefix-probing builder, kept only for
          ;; Amsterdam, re-executes prefixes on the same pool.  This proves
          ;; the counter sees every execution.
          (ethereum-lisp.engine-api::engine-rpc-build-viable-prepared-payload-by-probing
           store genesis attributes config candidates)
          (is (> executions (* 3 (length candidates))))
          (setf executions 0)
          (multiple-value-bind (block selected)
              (ethereum-lisp.engine-api:engine-rpc-build-viable-prepared-payload
               store genesis attributes config candidates)
            (is (<= executions (length candidates)))
            ;; The poisoned sender's four transactions are skipped.
            (is (= 44 (length selected)))
            (is (= 44 (length (block-transactions block)))))))
       ;; Oracle: the same build through fcU/getPayloadV5 is imported VALID by
       ;; an independent node through engine_newPayloadV4.
       (let* ((ethereum-lisp.engine-api::*engine-get-payload-improvement-seconds*
                30)
              (result (payload-building-probe node verifier 12 0)))
         (is (= 44 (getf result :transactions)))
         (is (string= "VALID" (getf result :verdict))))))
   :senders 12 :per-sender 4 :poisoned-p t :improvement-thread-p nil))

(deftest engine-payload-improvement-stops-early-and-never-regresses
  (:layer :integration :module :engine)
  (call-with-payload-building-nodes
   (lambda (node verifier)
     (let* ((store (ethereum-lisp.cli:devnet-node-store node))
            (config (ethereum-lisp.cli:devnet-node-config node))
            (open (payload-building-open-payload node 13)))
       (flet ((improve (stop-after)
                (let ((polls 0))
                  (ethereum-lisp.engine-api:engine-rpc-improve-prepared-payload
                   store config (payload-building-stored node open)
                   :stop-predicate
                   (and stop-after
                        (lambda () (> (incf polls) stop-after)))))))
         (is (= 0 (payload-building-transaction-count open)))
         ;; A pass cut after five candidates keeps its five: better than the
         ;; empty payload.  This is also the control that a cut pass really
         ;; builds less than the pool offers.
         (multiple-value-bind (payload stopped-p) (improve 5)
           (is stopped-p)
           (is (= 5 (payload-building-transaction-count payload))))
         ;; The cut pass did not mark the pool as seen: the next one rebuilds.
         (multiple-value-bind (payload stopped-p) (improve nil)
           (is (not stopped-p))
           (is (= 48 (payload-building-transaction-count payload))))
         ;; The pool changes; a pass cut short now builds less than the
         ;; stored payload, which is kept.
         (ethereum-lisp.txpool:engine-payload-store-put-pending-transaction
          store
          (payload-building-transaction
           config (first (payload-building-sender-keys 12)) 4
           :contract-call-p t))
         (multiple-value-bind (payload stopped-p) (improve 5)
           (is stopped-p)
           (is (= 48 (payload-building-transaction-count payload))))
         (is (= 48 (payload-building-transaction-count
                    (payload-building-stored node open))))
         ;; getPayload finishes the rebuild within its bound and the result
         ;; imports VALID on the independent node.
         (let* ((response
                  (payload-building-call
                   node
                   (payload-building-request
                    2 "engine_getPayloadV5"
                    (list (bytes-to-hex
                           (engine-prepared-payload-payload-id open))))))
                (payload
                  (payload-building-field
                   (payload-building-field response "result")
                   "executionPayload")))
           (is (= 49 (length (payload-building-field payload "transactions"))))
           (is (string= "VALID"
                        (payload-building-import-verdict verifier payload)))))))
   :senders 12 :per-sender 4 :improvement-thread-p nil))

(deftest devnet-payload-builder-steps-aside-for-engine-requests
  (:layer :integration :module :engine)
  ;; The builder holds the node's store guard while it selects.  With an
  ;; Engine request waiting for that guard it must stop before the next
  ;; transaction, step aside, and wake itself to finish later.
  (call-with-payload-building-nodes
   (lambda (node verifier)
     (declare (ignore verifier))
     (let ((shutdown (ethereum-lisp.cli:make-devnet-shutdown-controller))
           (yields 0))
       (flet ((pass (priority-pending-p)
                (devnet-peer-sync-call-with-function-overrides
                 (list (cons 'ethereum-lisp.cli::devnet-node-store-guard-priority-pending-p
                             (lambda (seen-node)
                               (declare (ignore seen-node))
                               priority-pending-p))
                       (cons 'ethereum-lisp.cli::devnet-node-yield-store-guard-to-priority
                             (lambda (seen-node)
                               (declare (ignore seen-node))
                               (incf yields))))
                 (lambda ()
                   (ethereum-lisp.cli::devnet-improve-open-payloads-once
                    node shutdown)))))
         (let ((open (payload-building-open-payload node 14)))
           (is (pass t))
           (is (= 1 yields))
           (is (= 0 (payload-building-transaction-count
                     (payload-building-stored node open))))
           ;; RED control: nobody waiting, the same pass fills the payload.
           (is (not (pass nil)))
           (is (= 1 yields))
           (is (= 48 (payload-building-transaction-count
                      (payload-building-stored node open))))))))
   :senders 12 :per-sender 4 :improvement-thread-p nil))
