(in-package #:ethereum-lisp.evm.internal)

;;;; Call tracing.
;;;;
;;;; Records the tree of calls a transaction makes: who called whom, with how
;;;; much gas and value, and what came back. This is the shape `callTracer`
;;;; reports, and it is what people actually reach for when a transaction did
;;;; something they did not expect.
;;;;
;;;; A CALL TRACER NEEDS CALL BOUNDARIES, NOT AN OPCODE HOOK. Every frame in the
;;;; tree corresponds to one EXECUTE-MESSAGE-CALL-CHILD, so two lines in that
;;;; function collect the whole thing. `structLog`, which reports every
;;;; instruction, would need a hook in the interpreter loop and would cost
;;;; something on every step; this costs a NIL check per call.
;;;;
;;;; TRACING IS OFF UNLESS SOMETHING BINDS THE TRACER. *EVM-CALL-TRACER* is NIL
;;;; by default and every hook is guarded by it, so an untraced execution pays
;;;; one special-variable read per call frame and allocates nothing.
;;;;
;;;; THE BINDING DOES NOT CROSS THREADS. A `let` on a special is thread-local,
;;;; so a tracer bound here is invisible to any thread spawned inside that
;;;; scope. That is fine because a traced execution runs on the thread that
;;;; asked for it -- but it is the reason this must never become a way to trace
;;;; the node's own block import from somewhere else.

(defvar *evm-call-tracer* nil
  "The tracer collecting the current call tree, or NIL when not tracing.")

(defvar *evm-trace-transfers-p* nil
  "True only while an RPC simulation is collecting ETH transfer pseudo-logs.")

(defstruct evm-log-tracer
  "Transient RPC log stream with geth-compatible block-global indices."
  (logs '() :type list)
  (indices '() :type list)
  (count 0 :type (integer 0 *)))

(defvar *evm-log-tracer* nil
  "Dynamically scoped RPC log tracer, or NIL outside transfer tracing.")

(defun evm-capture-trace-log (log)
  "Capture LOG in the transient RPC stream and always return LOG."
  (when *evm-log-tracer*
    (push log (evm-log-tracer-logs *evm-log-tracer*))
    (push (evm-log-tracer-count *evm-log-tracer*)
          (evm-log-tracer-indices *evm-log-tracer*))
    (incf (evm-log-tracer-count *evm-log-tracer*)))
  log)

(defun evm-log-tracer-snapshot ()
  "Return the current reversible stream frontier, excluding the index counter."
  (and *evm-log-tracer*
       (cons (evm-log-tracer-logs *evm-log-tracer*)
             (evm-log-tracer-indices *evm-log-tracer*))))

(defun evm-log-tracer-restore (snapshot)
  "Restore discarded frame logs without rewinding the block-global counter."
  (when *evm-log-tracer*
    (setf (evm-log-tracer-logs *evm-log-tracer*) (car snapshot)
          (evm-log-tracer-indices *evm-log-tracer*) (cdr snapshot))))

(defun evm-log-tracer-drain ()
  "Return one call's logs and indices in execution order, then clear the stream."
  (when *evm-log-tracer*
    (multiple-value-prog1
        (values (nreverse (evm-log-tracer-logs *evm-log-tracer*))
                (nreverse (evm-log-tracer-indices *evm-log-tracer*)))
      (setf (evm-log-tracer-logs *evm-log-tracer*) '()
            (evm-log-tracer-indices *evm-log-tracer*) '()))))

(defstruct (evm-call-frame
            (:constructor %make-evm-call-frame
                (&key type from to value gas input)))
  "One frame of a call tree. CALLS holds the children, in the order they ran."
  type
  from
  to
  (value 0)
  (gas 0)
  (input nil)
  (gas-used 0)
  (output nil)
  (error nil)
  (calls '()))

(defstruct (evm-call-tracer (:constructor make-evm-call-tracer ()))
  "A call tree under construction.

STACK is the frames currently open, innermost first. ROOT is the outermost
frame once one has been entered.

TOP-OUTPUT and TOP-FAILURE are what the transaction's own top-level frame
returned, noted by the transaction applier (EVM-CALL-TRACER-NOTE-TOP-LEVEL),
because that frame is not a child call and no hook below sees it."
  root
  (stack '())
  (top-output nil)
  (top-failure nil))

(defun evm-call-tracer-note-top-level (&key output failure)
  "Record the current transaction's top-level OUTPUT and FAILURE (:REVERTED,
an EVM-ERROR, a message string, or NIL) on the bound tracer, if any."
  (let ((tracer *evm-call-tracer*))
    (when tracer
      (setf (evm-call-tracer-top-output tracer) output
            (evm-call-tracer-top-failure tracer) failure)))
  nil)

(defun evm-call-trace-error-text (failure)
  "The error a frame that ended in FAILURE reports, in geth's words where the
failure is one geth names (core/vm/errors.go at 38271784), else our own."
  (cond
    ((null failure) nil)
    ((eq failure :reverted) "execution reverted")
    ((stringp failure) failure)
    ((typep failure 'evm-error)
     (let ((message (princ-to-string failure)))
       (flet ((prefix-p (prefix)
                (let ((end (min (length message) (length prefix))))
                  (string-equal prefix message :end2 end))))
         (cond
           ((search "code deposit out of gas" message)
            "contract creation code storage out of gas")
           ((or (prefix-p "EVM out of gas") (prefix-p "Precompile out of gas")
                (search "out of gas" message :test #'char-equal))
            "out of gas")
           ((prefix-p "Maximum EVM call depth") "max call depth exceeded")
           ((prefix-p "Insufficient balance") "insufficient balance for transfer")
           ((prefix-p "Invalid EVM jump destination") "invalid jump destination")
           ((search "not allowed in read-only" message) "write protection")
           (t message)))))
    (t (princ-to-string failure))))

(defun evm-call-tracer-enter (tracer &key type from to (value 0) (gas 0) input)
  "Open a frame. Returns the depth to unwind to, which EXIT takes back.

Returning the depth rather than the frame is what makes the pair robust: if a
condition unwinds past an EXIT that never ran, the next EXIT still restores the
stack to a consistent point instead of closing somebody else's frame."
  (let ((frame (%make-evm-call-frame :type type :from from :to to
                                     :value value :gas gas :input input))
        (depth (length (evm-call-tracer-stack tracer))))
    (if (evm-call-tracer-stack tracer)
        (push frame (evm-call-frame-calls (first (evm-call-tracer-stack tracer))))
        (setf (evm-call-tracer-root tracer) frame))
    (push frame (evm-call-tracer-stack tracer))
    depth))

(defun evm-call-tracer-exit (tracer depth &key (gas-used 0) output error)
  "Close the frame opened at DEPTH, recording what it returned."
  (let ((stack (evm-call-tracer-stack tracer)))
    (when stack
      (let ((frame (first stack)))
        (setf (evm-call-frame-gas-used frame) gas-used
              (evm-call-frame-output frame) output
              (evm-call-frame-error frame) error))
      ;; Unwind to DEPTH rather than popping once, so a frame whose EXIT was
      ;; skipped by an unwind does not leave the stack permanently deeper.
      (setf (evm-call-tracer-stack tracer)
            (nthcdr (- (length stack) depth) stack)))))

(defun evm-call-frame-children (frame)
  "FRAME's children in execution order.

They are pushed, so the list is reversed; doing it here rather than at push time
keeps entering a frame O(1)."
  (reverse (evm-call-frame-calls frame)))

(defun call-with-evm-call-trace (thunk &key type from to (value 0) (gas 0) input)
  "Run THUNK as one traced frame, or plainly when nothing is tracing.

THUNK returns (VALUES SUCCESS OUTPUT GAS-USED LOGS REFUND STATE-GAS EXIT-BUDGET
FAILURE); SUCCESS, OUTPUT and GAS-USED are recorded, FAILURE (:REVERTED, the
EVM-ERROR that ended the frame, or NIL) names the error, and all of them are
passed straight through, so a caller cannot tell tracing is on. A STATICCALL
frame carries no value, which geth's callTracer omits."
  (let ((tracer *evm-call-tracer*))
    (if (null tracer)
        (funcall thunk)
        (let ((depth (evm-call-tracer-enter
                      tracer :type type :from from :to to
                      :value (unless (equal type "STATICCALL") value)
                      :gas gas :input input))
              (recorded-p nil))
          (unwind-protect
               (multiple-value-call
                   (lambda (&rest values)
                     (let ((success (or (first values) 0))
                           (output (second values))
                           (gas-used (or (third values) 0))
                           (failure (eighth values)))
                       (evm-call-tracer-exit
                        tracer depth
                        :gas-used gas-used
                        ;; geth keeps the output of a success and of a revert;
                        ;; any other failure returns none.
                        :output (and (or (eql success 1) (eq failure :reverted))
                                     output)
                        :error (when (eql success 0)
                                 (evm-call-trace-error-text
                                  (or failure :reverted))))
                       (setf recorded-p t))
                     (values-list values))
                 (funcall thunk))
            ;; A condition escaping the thunk skips the recording above, and a
            ;; frame left open would swallow every later sibling as its child.
            (unless recorded-p
              (evm-call-tracer-exit tracer depth :error "execution failed")))))))

(defun call-with-evm-create-trace
    (thunk &key type from to (value 0) (gas 0) input)
  "Run THUNK, one CREATE or CREATE2, as a traced frame of TYPE, or plainly.

THUNK returns (VALUES SUCCESS-ADDRESS RETURN-DATA GAS-USED LOGS REFUND
STATE-GAS FAILURE DEPLOYED-CODE). As geth's callTracer does, a successful
frame's output is the deployed code, a reverted one's its revert data, and a
failed frame names no address (core/vm/evm.go create, eth/tracers/native/
call.go processOutput at 38271784)."
  (let ((tracer *evm-call-tracer*))
    (if (null tracer)
        (funcall thunk)
        (let ((depth (evm-call-tracer-enter tracer :type type :from from :to to
                                                   :value value :gas gas
                                                   :input input))
              (recorded-p nil))
          (unwind-protect
               (multiple-value-call
                   (lambda (&rest values)
                     (let* ((success-p (not (eql 0 (or (first values) 0))))
                            (return-data (second values))
                            (gas-used (or (third values) 0))
                            (failure (seventh values))
                            (deployed (eighth values))
                            (frame (first (evm-call-tracer-stack tracer))))
                       (evm-call-tracer-exit
                        tracer depth
                        :gas-used gas-used
                        :output (cond (success-p deployed)
                                      ((eq failure :reverted) return-data))
                        :error (unless success-p
                                 (evm-call-trace-error-text
                                  (or failure "contract creation failed"))))
                       (unless success-p
                         (setf (evm-call-frame-to frame) nil))
                       (setf recorded-p t))
                     (values-list values))
                 (funcall thunk))
            (unless recorded-p
              (evm-call-tracer-exit tracer depth :error "execution failed")))))))
