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
frame once one has been entered."
  root
  (stack '()))

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

THUNK returns (VALUES SUCCESS OUTPUT GAS-USED . rest); those are recorded and
passed straight through, so a caller cannot tell tracing is on."
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
                     (destructuring-bind
                         (&optional (success 0) output (gas-used 0) &rest ignored)
                         values
                       (declare (ignore ignored))
                       (evm-call-tracer-exit
                        tracer depth
                        :gas-used gas-used
                        :output output
                        ;; A zero success is a revert or an EVM failure. The
                        ;; frame is what says WHERE it happened; the reason
                        ;; itself is in the output when there was one.
                        :error (when (eql success 0) "execution reverted"))
                       (setf recorded-p t))
                     (values-list values))
                 (funcall thunk))
            ;; A condition escaping the thunk skips the recording above, and a
            ;; frame left open would swallow every later sibling as its child.
            (unless recorded-p
              (evm-call-tracer-exit tracer depth :error "execution failed")))))))
