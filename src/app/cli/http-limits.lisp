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
  (let* ((timeout
           (devnet-cli-http-request-timeout-seconds
            (getf options :http-read-timeout-seconds)
            (getf options :http-write-timeout-seconds)))
         (*engine-rpc-http-request-timeout-seconds*
           (if (and timeout (plusp timeout))
               timeout
               *engine-rpc-http-request-timeout-seconds*)))
    (funcall thunk)))
