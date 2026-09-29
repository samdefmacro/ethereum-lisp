(in-package #:ethereum-lisp.public-api)

;;;; debug_traceCall, debug_traceTransaction, debug_traceBlockBy* -- the call
;;;; tracer.
;;;;
;;;; Reports the tree of calls an execution makes: who called whom, with how
;;;; much gas and value, and what came back. The shape is geth's `callTracer`,
;;;; because that is what every tool that reads a trace already expects.
;;;;
;;;; ONLY callTracer, DELIBERATELY. `structLog` reports every instruction and
;;;; needs a hook in the interpreter loop that does not exist, and shipping a
;;;; `tracer` parameter that silently ignored what it was asked for would be
;;;; worse than refusing it.
;;;;
;;;; A BLOCK IS EXECUTED ONCE. debug_traceBlockBy* runs the block from its
;;;; parent's state through the same executor block import uses (pre-execution
;;;; system calls included) and attaches a fresh tracer to each transaction as
;;;; it is applied, as geth's traceBlock does (eth/tracers/api.go at 38271784):
;;;; work linear in the block, where replaying each transaction's prefix was
;;;; quadratic. debug_traceTransaction stops after its transaction.

(defun eth-rpc-trace-hex-bytes (bytes)
  "BYTES as hex, or NIL when there are none."
  (when bytes (bytes-to-hex bytes)))

(defun eth-rpc-call-frame-object (frame)
  "One call frame as the JSON object callTracer produces.

Fields a frame does not have are omitted rather than emitted as null, as geth's
callTracer omits them (eth/tracers/native/call.go callFrame, omitempty): no
`error` on a successful frame, no `calls` on a leaf, no `output` when nothing
was returned, no `value` on a STATICCALL, and no `to` on a failed creation. A
tool that switches on presence would misread nulls as values."
  (append
   (list (cons "type" (evm-call-frame-type frame))
         (cons "from" (when (evm-call-frame-from frame)
                        (address-to-hex (evm-call-frame-from frame)))))
   (when (evm-call-frame-to frame)
     (list (cons "to" (address-to-hex (evm-call-frame-to frame)))))
   (when (evm-call-frame-value frame)
     (list (cons "value" (quantity-to-hex (evm-call-frame-value frame)))))
   (list (cons "gas" (quantity-to-hex (or (evm-call-frame-gas frame) 0)))
         (cons "gasUsed"
               (quantity-to-hex (or (evm-call-frame-gas-used frame) 0)))
         (cons "input" (or (eth-rpc-trace-hex-bytes (evm-call-frame-input frame))
                           "0x")))
   (let ((output (evm-call-frame-output frame)))
     (when (plusp (length output))
       (list (cons "output" (bytes-to-hex output)))))
   (when (evm-call-frame-error frame)
     (list (cons "error" (evm-call-frame-error frame))))
   (let ((children (evm-call-frame-children frame)))
     (when children
       (list (cons "calls" (mapcar #'eth-rpc-call-frame-object children)))))))

(defun eth-rpc-trace-tracer-name (options method)
  "The tracer OPTIONS asks for, defaulting to callTracer.

geth's default is structLog, which we do not have. Defaulting to the one we DO
have, and refusing the one we do not by name, is the honest arrangement: a
client either gets what it asked for or is told plainly that it cannot."
  (let ((name (and options
                   (json-object-p options)
                   (json-object-field options "tracer"))))
    (cond
      ((or (null name) (equal name "callTracer")) "callTracer")
      ((stringp name)
       (invalid-parameters-fail
        "~A supports only the callTracer, not ~A" method name))
      (t (invalid-parameters-fail "~A tracer must be a string" method)))))

(defun eth-rpc-traced-call-frame (object block store config method
                                  &key gas-limit)
  "Simulate a call with the tracer attached and return its root frame.

The tracer is bound around the simulation and nowhere wider: everything else
executing in this image must stay untraced, and a special variable bound too
broadly would quietly start collecting frames for block import."
  (let ((tracer (make-evm-call-tracer)))
    ;; The OUTERMOST frame is opened here rather than in the EVM, because the
    ;; call being traced is not made by any other call -- nothing inside the
    ;; interpreter ever enters it, so without this the tree would be rooted at
    ;; the first call the target itself makes and the request's own frame would
    ;; be missing.
    (multiple-value-bind (sender transaction)
        (eth-rpc-call-object-transaction object (block-header block) method
                                         config :gas-limit-override gas-limit)
      (let ((*evm-call-tracer* tracer))
        (let ((depth (evm-call-tracer-enter
                      tracer
                      :type "CALL"
                      :from sender
                      :to (transaction-to transaction)
                      :value (transaction-value transaction)
                      :gas (transaction-gas-limit transaction)
                      :input (transaction-data transaction))))
          ;; A revert is a RESULT here, not an error. debug_traceCall exists
          ;; largely to explain reverts, so failing the request the way
          ;; eth_call does would refuse to answer the very question being
          ;; asked.
          (multiple-value-bind (status output gas-used)
              (handler-case
                  (eth-rpc-simulate-call-object object block store config
                                                method :gas-limit gas-limit)
                (ethereum-lisp.engine-api:engine-rpc-error ()
                  (values :failed nil 0))
                (ethereum-lisp.validation:block-validation-error ()
                  (values :failed nil 0)))
            (evm-call-tracer-exit
             tracer depth
             :gas-used (or gas-used 0)
             :output output
             :error (unless (eth-rpc-call-status-success-p status)
                      "execution reverted"))))))
    (evm-call-tracer-root tracer)))

(defun engine-rpc-handle-debug-trace-call (params store config)
  "debug_traceCall: [callObject, blockId, tracerConfig?]."
  (unless (<= 1 (length params) 3)
    (block-validation-fail
     "debug_traceCall params must contain a call object, an optional block id ~
      and an optional tracer config"))
  (eth-rpc-trace-tracer-name (third params) "debug_traceCall")
  (let* ((block (eth-rpc-state-block-param
                 (list (if (>= (length params) 2) (second params) "latest"))
                 store
                 "debug_traceCall"))
         (frame (eth-rpc-traced-call-frame
                 (first params) block store config "debug_traceCall")))
    (unless frame
      ;; No frame at all means execution never entered a call -- a plain value
      ;; transfer, or a rejection before the first frame opened.
      (block-validation-fail "debug_traceCall produced no call frames"))
    (eth-rpc-call-frame-object frame)))

(defun eth-rpc-trace-applied-transaction
    (state transaction chain-id apply-options)
  "Apply TRANSACTION to STATE, as the block executor's applier does, with a
fresh call tracer bound, and return its root frame.

The root is the transaction's own frame, which no call hook sees: geth's
callTracer takes its type, sender, recipient (or created address), value, gas
limit and input from the transaction, its gasUsed from the receipt (OnTxEnd),
and its output and error from the top-level execution, which the applier notes
on the tracer (EVM-CALL-TRACER-NOTE-TOP-LEVEL)."
  (let* ((sender
           (or (transaction-sender transaction :expected-chain-id chain-id)
               (block-validation-fail "Traced transaction sender recovery failed")))
         (to (transaction-to transaction))
         (created
           (unless to
             (execution-create-address
              sender
              (let ((account (state-db-get-account state sender)))
                (if account (state-account-nonce account) 0)))))
         (tracer (make-evm-call-tracer)))
    (let ((*evm-call-tracer* tracer))
      (let ((depth (evm-call-tracer-enter
                    tracer
                    :type (if to "CALL" "CREATE")
                    :from sender
                    :to (or to created)
                    :value (transaction-value transaction)
                    :gas (transaction-gas-limit transaction)
                    :input (transaction-data transaction)))
            (receipt (first (apply #'apply-signed-message-list
                                   state (list transaction)
                                   :expected-chain-id chain-id
                                   apply-options))))
        (let ((failed-p (eql 0 (receipt-status receipt)))
              (failure (evm-call-tracer-top-failure tracer))
              (output (evm-call-tracer-top-output tracer)))
          (evm-call-tracer-exit
           tracer depth
           ;; A one-transaction list: its cumulative gas is its own.
           :gas-used (receipt-cumulative-gas-used receipt)
           :output (and (or (not failed-p) (eq failure :reverted)) output)
           :error (when failed-p
                    (evm-call-trace-error-text (or failure :reverted))))
          (when (and failed-p created)
            (setf (evm-call-frame-to (evm-call-tracer-root tracer)) nil)))))
    (evm-call-tracer-root tracer)))

(defun eth-rpc-trace-block-frames
    (state block config &key block-hashes parent-header (last-index nil))
  "Execute BLOCK once from STATE, its parent's state, and return the root call
frame of each transaction, in order.

The block runs through EXECUTE-BLOCK-WITH-MESSAGE-APPLIER, the executor block
import uses, so its pre-execution system calls (beacon root, parent hash) run
first, as geth's traceBlock runs core.PreExecution. The applier applies one
transaction at a time with a tracer bound (ETH-RPC-TRACE-APPLIED-TRANSACTION)
and leaves the executor once the last wanted transaction has run: nothing after
the transactions is needed, and STATE is the caller's private copy. With
LAST-INDEX, the transactions before it are applied untraced and the result is
the one frame at LAST-INDEX, as geth's traceTransaction replays its prefix."
  (let ((chain-id (chain-config-chain-id config))
        (block-header (block-header block))
        (frames '()))
    (catch 'eth-rpc-trace-block-frames
      (apply #'execute-block-with-message-applier
             state
             (block-transactions block)
             (lambda (state transactions &rest options)
               (loop for transaction in transactions
                     for index from 0
                     do (if (or (null last-index) (= index last-index))
                            (push (eth-rpc-trace-applied-transaction
                                   state transaction chain-id options)
                                  frames)
                            (apply #'apply-signed-message-list
                                   state (list transaction)
                                   :expected-chain-id chain-id options))
                        (when (eql index last-index)
                          (return)))
               (throw 'eth-rpc-trace-block-frames nil))
             :header (engine-payload-store-copy-block-header block-header)
             :parent-header parent-header
             :chain-config config
             :block-hashes (or block-hashes (make-hash-table))
             :ommers (block-ommers block)
             (append
              (when (block-withdrawals-present-p block)
                (list :withdrawals (block-withdrawals block)
                      :withdrawals-supplied-p t))
              (when (block-requests-present-p block)
                (list :requests (block-requests block)
                      :requests-supplied-p t))
              (when (block-block-access-list-present-p block)
                (list :block-access-list (block-block-access-list block)
                      :block-access-list-supplied-p t)))))
    (nreverse frames)))

(defun eth-rpc-trace-block-from-store (block store config &key last-index)
  "ETH-RPC-TRACE-BLOCK-FRAMES for BLOCK, from STORE's parent state."
  (let* ((header (block-header block))
         (parent (chain-store-known-block
                  store (block-header-parent-hash header)))
         (state (and parent (chain-store-state-db store (block-hash parent)))))
    (unless state
      (engine-rpc-fail -32000
                       (format nil "required historical state unavailable")))
    (eth-rpc-trace-block-frames
     state block config
     :block-hashes (chain-store-block-hashes-for-header store header)
     :parent-header (block-header parent)
     :last-index last-index)))

(defun eth-rpc-trace-transaction-location (location store config)
  (let ((frames (eth-rpc-trace-block-from-store
                 (engine-transaction-location-block location) store config
                 :last-index (engine-transaction-location-index location))))
    (eth-rpc-call-frame-object (first frames))))

(defun engine-rpc-handle-debug-trace-transaction (params store config)
  (unless (<= 1 (length params) 2)
    (block-validation-fail
     "debug_traceTransaction params must contain transaction hash and optional tracer config"))
  (eth-rpc-trace-tracer-name (second params) "debug_traceTransaction")
  (let* ((hash
           (json-rpc-hash32
            (first params) "debug_traceTransaction transaction hash"))
         (location (chain-store-transaction-location store hash)))
    (unless location
      (engine-rpc-fail -32000
                       "debug_traceTransaction transaction not found"))
    (eth-rpc-trace-transaction-location location store config)))

(defun eth-rpc-debug-trace-block (block store config)
  ;; Execution APIs e5d1bb60 `src/debug/trace.yaml` requires an error here:
  ;; genesis has no parent state from which a trace can replay. Reject it even
  ;; when it contains no transactions, before the empty loop returns `[]`.
  (when (zerop (block-header-number (block-header block)))
    (engine-rpc-fail -32000 "genesis is not traceable"))
  (eth-rpc-json-array
   (loop for transaction in (block-transactions block)
         for frame in (eth-rpc-trace-block-from-store block store config)
         collect
         (list
          (cons "txHash" (hash32-to-hex (transaction-hash transaction)))
          (cons "result" (eth-rpc-call-frame-object frame))))))

(defun engine-rpc-handle-debug-trace-block-by-hash (params store config)
  (unless (<= 1 (length params) 2)
    (block-validation-fail
     "debug_traceBlockByHash params must contain block hash and optional tracer config"))
  (eth-rpc-trace-tracer-name (second params) "debug_traceBlockByHash")
  (let ((block
          (chain-store-known-block
           store
           (json-rpc-hash32
            (first params) "debug_traceBlockByHash block hash"))))
    (unless block
      (engine-rpc-fail -32000 "debug_traceBlockByHash block not found"))
    (eth-rpc-debug-trace-block block store config)))

(defun engine-rpc-handle-debug-trace-block-by-number (params store config)
  (unless (<= 1 (length params) 2)
    (block-validation-fail
     "debug_traceBlockByNumber params must contain block number and optional tracer config"))
  (eth-rpc-trace-tracer-name (second params) "debug_traceBlockByNumber")
  (let ((block
          (eth-rpc-block-param
           (list (first params)) store "debug_traceBlockByNumber")))
    (unless block
      (engine-rpc-fail -32000 "debug_traceBlockByNumber block not found"))
    (eth-rpc-debug-trace-block block store config)))

(defun engine-rpc-handle-debug-set-head (params store config)
  (unless (= 1 (length params))
    (block-validation-fail
     "debug_setHead params must contain exactly one block id"))
  (let ((block (eth-rpc-block-param params store "debug_setHead")))
    (unless block
      (block-validation-fail "debug_setHead block not found"))
    (let ((current (chain-store-latest-block store)))
      (when (or (and current
                     (chain-config-post-merge-p
                      config
                      (block-header-number (block-header current))))
                (chain-config-post-merge-p
                 config (block-header-number (block-header block))))
      (block-validation-fail
       "debug_setHead cannot mutate a post-Merge canonical view; use Engine forkchoiceUpdated")))
    (ethereum-lisp.canonical-chain:chain-store-set-canonical-head
     store (block-hash block)
     :expected-chain-id (chain-config-chain-id config)
     :chain-config config)
    nil))
