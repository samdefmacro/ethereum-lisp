(in-package #:ethereum-lisp.cli)

;;;; CLI-scoped HTTP request limits.

(defun devnet-cli-http-request-timeout-seconds (read-timeout write-timeout)
  "Combine geth-style read and write timeouts into one request deadline.

The server answers a request within a single deadline spanning the read and the
response write, so the two configured budgets add. Returning NIL leaves the
built-in default in place."
  (cond
    ((and read-timeout write-timeout) (+ read-timeout write-timeout))
    (read-timeout read-timeout)
    (write-timeout write-timeout)
    (t nil)))

(defun call-with-devnet-cli-http-limits (options thunk)
  "Run THUNK with request limits taken from OPTIONS."
  (unless (functionp thunk)
    (error "Devnet HTTP limits thunk must be a function"))
  ;; These are assigned rather than dynamically bound on purpose. The node
  ;; serves each listener on its own thread, and a LET binding is thread-local
  ;; in SBCL, so a spawned listener would read the global value and silently
  ;; ignore everything configured here. Startup configuration has to be visible
  ;; to every thread; the previous values are restored so callers stay scoped.
  (let ((timeout
          (devnet-cli-http-request-timeout-seconds
           (getf options :http-read-timeout-seconds)
           (getf options :http-write-timeout-seconds)))
        (max-clients (getf options :http-max-clients))
        (previous-timeout *engine-rpc-http-request-timeout-seconds*)
        (previous-max-clients *engine-rpc-http-max-concurrent-connections*))
    (unwind-protect
         (progn
           (when (and timeout (plusp timeout))
             (setf *engine-rpc-http-request-timeout-seconds* timeout))
           (when (and max-clients (plusp max-clients))
             (setf *engine-rpc-http-max-concurrent-connections* max-clients))
           (funcall thunk))
      (setf *engine-rpc-http-request-timeout-seconds* previous-timeout
            *engine-rpc-http-max-concurrent-connections* previous-max-clients))))
