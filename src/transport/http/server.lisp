(in-package #:ethereum-lisp.rpc-http)

(defun engine-rpc-http-await-next-request (input-stream &optional stop-p)
  "Wait between requests on a keep-alive connection, without parking on it.

Returns :REQUEST once the next request's first character is buffered (PEEK-CHAR
leaves it there for the reader), :EOF when the peer closed the connection, and
:STOP once STOP-P answers true. Signals when the keep-alive idle budget in
*ENGINE-RPC-HTTP-IDLE-TIMEOUT-SECONDS* expires, exactly as the single blocking
wait it replaces did.

The wait polls instead of blocking for the whole budget because a worker parked
in one long read cannot notice that its listener was asked to stop. That is why
a consensus client's pooled connection, busy or idle, held a stopping node past
a supervisor's grace period until it was SIGKILLed. Waking every
*ENGINE-RPC-HTTP-STOP-CHECK-INTERVAL-SECONDS* bounds the delay to one interval;
the deadline the intervals are measured against is the original one, so normal
operation still closes an idle connection at the same moment."
  (unless (or (null stop-p) (functionp stop-p))
    (block-validation-fail
     "Engine RPC HTTP stop predicate must be a function"))
  #-sbcl
  (if (and stop-p (funcall stop-p))
      :stop
      (if (eq :eof (peek-char nil input-stream nil :eof)) :eof :request))
  #+sbcl
  (let* ((idle-timeout *engine-rpc-http-idle-timeout-seconds*)
         (interval *engine-rpc-http-stop-check-interval-seconds*)
         (deadline
           (and idle-timeout
                (+ (get-internal-real-time)
                   (* idle-timeout internal-time-units-per-second)))))
    (flet ((peek ()
             (if (eq :eof (peek-char nil input-stream nil :eof))
                 :eof
                 :request)))
      (when (or (null deadline) (null interval) (not (plusp interval)))
        ;; Nothing to divide, or polling turned off: keep the original wait.
        (return-from engine-rpc-http-await-next-request
          (cond ((and stop-p (funcall stop-p)) :stop)
                (deadline (engine-rpc-http-with-idle-deadline (peek)))
                (t (peek)))))
      (loop
        (when (and stop-p (funcall stop-p))
          (return :stop))
        (let ((remaining (/ (- deadline (get-internal-real-time))
                            internal-time-units-per-second)))
          (unless (plusp remaining)
            (error "HTTP connection exceeded the ~A second idle deadline"
                   idle-timeout))
          (let ((result
                  (handler-case
                      (sb-sys:with-deadline (:seconds (min interval remaining))
                        (peek))
                    (sb-sys:deadline-timeout () nil))))
            (when result
              (return result))))))))

(defun engine-rpc-http-service-handle-stream
    (service input-stream output-stream &key stop-p)
  (unless (typep service 'engine-rpc-http-service)
    (block-validation-fail
     "Engine RPC HTTP service must be engine-rpc-http-service"))
  (unless (or (null stop-p) (functionp stop-p))
    (block-validation-fail
     "Engine RPC HTTP stop predicate must be a function"))
  (let ((sink (engine-rpc-http-service-telemetry-sink service))
        (fields `(("endpoint" . ,(engine-rpc-http-service-endpoint service))
                  ("host" . ,(engine-rpc-http-service-host service))
                  ("port" . ,(engine-rpc-http-service-port service)))))
    (ethereum-lisp.telemetry:telemetry-log
     :debug
     "engine.rpc.http.stream.start"
     :sink sink
     :fields fields)
    (unwind-protect
         (loop with last-response = nil
               with first-request-p = t
               ;; The first request starts under the normal request deadline.
               ;; Only a reused connection gets the longer keep-alive wait.
               ;; The stop is consulted HERE and nowhere else in this loop: a
               ;; request already in flight is answered in full, and only the
               ;; wait for the NEXT one is cut short. Dropping a response
               ;; mid-write would make a graceful stop worse than a SIGKILL.
               do (unless first-request-p
                    (let ((next
                            (engine-rpc-http-await-next-request
                             input-stream stop-p)))
                      (unless (eq next :request)
                        (return last-response))))
               do (multiple-value-bind (response close-p)
                      (engine-rpc-http-with-request-deadline
                        (rpc-http-handle-stream
                         input-stream
                         output-stream
                         (engine-rpc-http-service-rpc-context service)
                         :jwt-secret
                         (engine-rpc-http-service-jwt-secret service)
                         :now-provider
                         (engine-rpc-http-service-now-provider service)
                         :rpc-prefix
                         (engine-rpc-http-service-rpc-prefix service)
                         :cors-origins
                         (engine-rpc-http-service-cors-origins service)
                         :allowed-hosts
                         (engine-rpc-http-service-allowed-hosts service)
                         :persistent-p t
                         :telemetry-sink sink
                         :telemetry-fields fields))
                    (when response
                      (setf last-response response))
                    (setf first-request-p nil)
                    (when close-p
                      (return last-response))))
      (ethereum-lisp.telemetry:telemetry-metric
       "engine.rpc.http.streams"
       1
       :sink sink
       :fields fields)
      (ethereum-lisp.telemetry:telemetry-log
       :debug
       "engine.rpc.http.stream.finish"
       :sink sink
       :fields fields))))

(defun engine-rpc-http-serve-connection (service connection sink fields
                                         &key stop-p)
  "Serve CONNECTION to completion, containing any fault to that connection.

A peer that disappears mid-response signals on the socket write. That must end
the connection, not the listener: an escaping error unwinds the accept loop and
the supervising node treats it as a shutdown request."
  (handler-case
      (unwind-protect
           (engine-rpc-http-service-handle-stream
            service
            (engine-rpc-http-connection-input-stream connection)
            (engine-rpc-http-connection-output-stream connection)
            :stop-p stop-p)
        (ignore-errors
         (engine-rpc-http-connection-close connection)))
    (error (condition)
      (ethereum-lisp.telemetry:telemetry-log
       :warn
       "engine.rpc.http.connection.error"
       :sink sink
       :fields (append fields
                       (list (cons "error" (format nil "~A" condition))))))))

(defun engine-rpc-http-worker-drain-timeout-seconds (&optional stopping-p)
  "Return the shutdown budget for in-flight connection workers.

Without a stop in progress the budget must outlast a request running to its own
deadline on a connection that then waits out its whole keep-alive idle budget.

STOPPING-P collapses it to *ENGINE-RPC-HTTP-SHUTDOWN-DRAIN-SECONDS*, because
once a stop has been requested the per-connection loop returns between requests
and the only thing left to wait for is a request already in progress. Keeping
the idle timeout in that budget is what let a consensus client's pooled Engine
connection be served straight through a supervisor's grace period."
  (if stopping-p
      *engine-rpc-http-shutdown-drain-seconds*
      (+ 5
         (or *engine-rpc-http-request-timeout-seconds* 0)
         (or *engine-rpc-http-idle-timeout-seconds* 0))))

(defun engine-rpc-http-drain-connection-workers (semaphore limit
                                                 &optional stopping-p)
  "Wait for in-flight connection workers to finish, returning true when drained.

Reacquiring every permit proves no worker still holds one, which avoids keeping
a thread list that would grow for the lifetime of the listener. The budget has
to outlast a request that is itself running to its deadline, or the drain would
report success while a worker still holds a connection."
  #+sbcl
  (if (null semaphore)
      t
      (let ((deadline
             (+ (get-internal-real-time)
                (* (engine-rpc-http-worker-drain-timeout-seconds stopping-p)
                   internal-time-units-per-second))))
        (loop for acquired from 0 below limit
              do (let ((remaining (/ (- deadline (get-internal-real-time))
                                     internal-time-units-per-second)))
                   (unless (and (plusp remaining)
                                (sb-thread:wait-on-semaphore
                                 semaphore :timeout remaining))
                     ;; Give back what was reclaimed so a caller that keeps the
                     ;; semaphore does not see permits vanish.
                     (loop repeat acquired
                           do (sb-thread:signal-semaphore semaphore))
                     (return nil)))
              finally (return t))))
  #-sbcl
  (progn (declare (ignore semaphore limit stopping-p)) t))

(defun engine-rpc-http-service-concurrency (service &optional (override :default))
  "Return SERVICE's effective socket-worker budget, or NIL for serial I/O.

OVERRIDE is an explicit per-listener limit when it is not :DEFAULT."
  (let ((limit
          (if (eq override :default)
              (or *engine-rpc-http-max-concurrent-connections*
                  (and
                   (engine-rpc-http-service-request-guarded-p service)
                   +engine-rpc-http-default-guarded-connections+))
              override)))
    (and limit (integerp limit) (plusp limit) limit)))

(defun engine-rpc-http-service-serve-listener
    (service listener &key max-connections stop-p (concurrency :default))
  (unless (typep service 'engine-rpc-http-service)
    (block-validation-fail
     "Engine RPC HTTP service must be engine-rpc-http-service"))
  (unless (typep listener 'engine-rpc-http-listener)
    (block-validation-fail
     "Engine RPC HTTP listener must be engine-rpc-http-listener"))
  (unless (or (null max-connections)
              (and (integerp max-connections) (<= 0 max-connections)))
    (block-validation-fail
     "Engine RPC HTTP max connections must be non-negative"))
  (unless (or (eq concurrency :default)
              (null concurrency)
              (and (integerp concurrency) (<= 0 concurrency)))
    (block-validation-fail
     "Engine RPC HTTP concurrency must be non-negative, NIL, or :DEFAULT"))
  (let* ((served 0)
        (stop-p (or stop-p (lambda () nil)))
        (concurrency
          (engine-rpc-http-service-concurrency service concurrency))
        (worker-slots
          #+sbcl (when concurrency
                   (sb-thread:make-semaphore :count concurrency
                                             :name "ethereum-lisp-rpc-http"))
          #-sbcl nil)
        ;; Accepted connections that are still being served. Closing a listening
        ;; socket does not touch an established one, so without this the only
        ;; thing that ever released a connection the drain gave up on was the
        ;; process exiting.
        (open-connections '())
        (open-connections-lock
          #+sbcl (sb-thread:make-mutex
                  :name "ethereum-lisp-rpc-http-connections")
          #-sbcl nil)
        (sink (engine-rpc-http-service-telemetry-sink service))
        (fields `(("endpoint" . ,(engine-rpc-http-listener-endpoint listener))
                  ("host" . ,(engine-rpc-http-service-host service))
                  ("port" . ,(engine-rpc-http-service-port service)))))
    (unless (functionp stop-p)
      (block-validation-fail
       "Engine RPC HTTP stop predicate must be a function"))
    (flet ((register-connection (connection)
             #+sbcl
             (sb-thread:with-mutex (open-connections-lock)
               (push connection open-connections))
             #-sbcl
             (push connection open-connections)
             connection)
           (forget-connection (connection)
             #+sbcl
             (sb-thread:with-mutex (open-connections-lock)
               (setf open-connections (delete connection open-connections)))
             #-sbcl
             (setf open-connections (delete connection open-connections))
             nil)
           (close-abandoned-connections ()
             (let ((abandoned
                     #+sbcl
                     (sb-thread:with-mutex (open-connections-lock)
                       (prog1 open-connections
                         (setf open-connections '())))
                     #-sbcl
                     (prog1 open-connections
                       (setf open-connections '()))))
               (dolist (connection abandoned)
                 (ignore-errors
                  (engine-rpc-http-connection-close connection)))
               (length abandoned))))
      (ethereum-lisp.telemetry:telemetry-log
       :info
       "engine.rpc.http.listener.start"
       :sink sink
       :fields fields)
      (unwind-protect
           (loop until (or (and max-connections (>= served max-connections))
                           (funcall stop-p))
                 for connection = (handler-case
                                      (engine-rpc-http-listener-accept listener)
                                    (error (condition)
                                      (if (funcall stop-p)
                                          nil
                                          (error condition))))
                 while connection
                 do (if worker-slots
                        (progn
                          ;; Block until a worker slot frees, so an unbounded
                          ;; number of peers cannot spawn unbounded threads.
                          #+sbcl (sb-thread:wait-on-semaphore worker-slots)
                          (register-connection connection)
                          #+sbcl
                          (sb-thread:make-thread
                           (let ((connection connection))
                             (lambda ()
                               (unwind-protect
                                    (handler-case
                                        (engine-rpc-http-serve-connection
                                         service connection sink fields
                                         :stop-p stop-p)
                                      (serious-condition (condition)
                                        ;; Thread boundary: STORAGE-CONDITION is
                                        ;; not an ERROR, but must not escape and
                                        ;; terminate an sbcl --script process.
                                        (ethereum-lisp.telemetry:telemetry-log
                                         :warn
                                         "engine.rpc.http.connection.error"
                                         :sink sink
                                         :fields
                                         (append
                                          fields
                                          `(("error" .
                                             ,(princ-to-string condition)))))))
                                 (forget-connection connection)
                                 (sb-thread:signal-semaphore worker-slots))))
                           :name "ethereum-lisp-rpc-http-connection"))
                        (progn
                          (register-connection connection)
                          (unwind-protect
                               (engine-rpc-http-serve-connection
                                service connection sink fields :stop-p stop-p)
                            (forget-connection connection))))
                    (incf served))
        ;; Let in-flight workers finish before the listener is torn down. Once a
        ;; stop has been requested that budget is the short one: the connection
        ;; loops now return between requests, so a worker still holding a permit
        ;; is answering a request, not waiting for one.
        (engine-rpc-http-drain-connection-workers
         worker-slots concurrency (ignore-errors (funcall stop-p)))
        ;; Past that budget the connection is abandoned, and go-ethereum's
        ;; http.Server closes what its Shutdown deadline could not drain rather
        ;; than leaving the socket to the process exit.
        (let ((abandoned (close-abandoned-connections)))
          (when (plusp abandoned)
            (ethereum-lisp.telemetry:telemetry-log
             :warn
             "engine.rpc.http.listener.abandoned"
             :sink sink
             :fields (append fields
                             (list (cons "connections"
                                         (princ-to-string abandoned)))))))
        (ethereum-lisp.telemetry:telemetry-metric
         "engine.rpc.http.listener.connections"
         served
         :sink sink
         :fields fields)
        (ethereum-lisp.telemetry:telemetry-log
         :info
         "engine.rpc.http.listener.finish"
         :sink sink
         :fields fields)
        (engine-rpc-http-listener-close listener))
      served)))
