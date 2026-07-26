(in-package #:ethereum-lisp.public-api)

;;;; debug_traceCall — the call tracer.
;;;;
;;;; Reports the tree of calls an execution makes: who called whom, with how
;;;; much gas and value, and what came back. The shape is geth's `callTracer`,
;;;; because that is what every tool that reads a trace already expects.
;;;;
;;;; ONLY callTracer, AND ONLY traceCall, DELIBERATELY. `structLog` reports
;;;; every instruction and needs a hook in the interpreter loop that does not
;;;; exist; `debug_traceTransaction` additionally needs the preceding
;;;; transactions of its block replayed to reach the right pre-state. Both are
;;;; real work rather than an afternoon, and shipping a `tracer` parameter that
;;;; silently ignored what it was asked for would be worse than refusing it.

(defun eth-rpc-trace-hex-bytes (bytes)
  "BYTES as hex, or NIL when there are none.

An absent `output` and an empty one mean different things to a client reading a
trace, so an empty byte string is reported as 0x rather than dropped."
  (when bytes (bytes-to-hex bytes)))

(defun eth-rpc-call-frame-object (frame)
  "One call frame as the JSON object callTracer produces.

Fields a frame does not have are omitted rather than emitted as null: geth
omits `error` on a successful frame and `calls` on a leaf, and a tool that
switches on presence would misread nulls as values."
  (append
   (list (cons "type" (evm-call-frame-type frame))
         (cons "from" (when (evm-call-frame-from frame)
                        (address-to-hex (evm-call-frame-from frame))))
         (cons "to" (when (evm-call-frame-to frame)
                      (address-to-hex (evm-call-frame-to frame))))
         (cons "value" (quantity-to-hex (or (evm-call-frame-value frame) 0)))
         (cons "gas" (quantity-to-hex (or (evm-call-frame-gas frame) 0)))
         (cons "gasUsed"
               (quantity-to-hex (or (evm-call-frame-gas-used frame) 0)))
         (cons "input" (or (eth-rpc-trace-hex-bytes (evm-call-frame-input frame))
                           "0x")))
   (let ((output (eth-rpc-trace-hex-bytes (evm-call-frame-output frame))))
     (when output (list (cons "output" output))))
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
