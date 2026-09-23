(in-package #:ethereum-lisp.cli)

;;;; Devnet listener startup and service lifetime orchestration.

(defun start-devnet-node-listeners
    (node engine-listener public-listener
     &key max-connections stop-p shutdown-controller on-listeners-ready
          p2p-listener
          (http-concurrency (if max-connections 0 :default)))
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (unless (typep engine-listener 'engine-rpc-http-listener)
    (error "Devnet Engine listener must be engine-rpc-http-listener"))
  (when (and public-listener
             (not (typep public-listener 'engine-rpc-http-listener)))
    (error "Devnet public listener must be engine-rpc-http-listener"))
  (when (and stop-p (not (functionp stop-p)))
    (error "Devnet stop predicate must be a function"))
  (when (and shutdown-controller
             (not (typep shutdown-controller 'devnet-shutdown-controller)))
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (when (and on-listeners-ready (not (functionp on-listeners-ready)))
    (error "Devnet listener-ready callback must be a function"))
  (when (and p2p-listener (not (typep p2p-listener 'eth-sync-listener)))
    (error "Devnet p2p listener must be eth-sync-listener"))
  (unless (or (eq http-concurrency :default)
              (null http-concurrency)
              (and (integerp http-concurrency) (<= 0 http-concurrency)))
    (error "Devnet HTTP concurrency must be non-negative, NIL, or :DEFAULT"))
  #-sbcl
  (declare (ignore node engine-listener public-listener max-connections stop-p
                   shutdown-controller on-listeners-ready http-concurrency))
  #-sbcl
  (error "Devnet split listener serving requires SBCL threads")
  #+sbcl
  (let* ((shutdown-controller
           (or shutdown-controller (make-devnet-shutdown-controller)))
         (stop-requested-p
           (lambda ()
             (or (devnet-shutdown-requested-p shutdown-controller)
                 (and stop-p (funcall stop-p)))))
         (engine-count nil)
         (engine-error nil)
         (public-count nil)
         (public-error nil)
         (txpool-maintenance-error nil)
         (txpool-maintenance-thread nil)
         (payload-improvement-error nil)
         (payload-improvement-thread nil)
         (rejournal-error nil)
         (rejournal-thread nil)
         (dev-period-error nil)
         (dev-period-thread nil)
         (dialer-error nil)
         (dialer-thread nil)
         (dialer-sessions nil)
         (sync-coordinator-error nil)
         (sync-coordinator-thread nil)
         (discovery-error nil)
         (discovery-thread nil)
         (discovery-server-error nil)
         (discovery-server-thread nil)
         (p2p-error nil)
         (p2p-thread nil)
         (p2p-sessions nil)
         (metrics-error nil)
         (metrics-thread nil)
         (ws-error nil)
         (ws-thread nil)
         (ws-sessions nil))
    (devnet-shutdown-controller-register-listeners
     shutdown-controller engine-listener public-listener)
    ;; First, because it is the only worker here that BINDS a port. A metrics
    ;; port already in use must fail the node before any other thread exists,
    ;; rather than after -- there is no unwind-protect covering them yet, so a
    ;; failure further down this sequence would leave them running.
    (setf metrics-thread
          (devnet-start-metrics-server-thread
           node
           shutdown-controller
           (lambda (condition)
             (setf metrics-error condition))))
    ;; Also before the ready callback, and for the same reason: it binds a port,
    ;; and a port already in use must fail the node rather than leave the
    ;; endpoint quietly missing.
    (multiple-value-setq (ws-thread ws-sessions)
      (devnet-start-ws-server-thread
       node
       shutdown-controller
       (lambda (condition)
         (setf ws-error condition))))
    (handler-case
        (when on-listeners-ready
          (funcall on-listeners-ready engine-listener public-listener))
      (error (condition)
        (devnet-shutdown-request shutdown-controller)
        (error condition)))
    (setf rejournal-thread
          (devnet-start-rejournal-thread
           node
           shutdown-controller
           (lambda (condition)
             (setf rejournal-error condition))))
    (setf txpool-maintenance-thread
          (devnet-start-txpool-maintenance-thread
           node
           shutdown-controller
           (lambda (condition)
             (setf txpool-maintenance-error condition))))
    (setf payload-improvement-thread
          (devnet-start-payload-improvement-thread
           node
           shutdown-controller
           (lambda (condition)
             (setf payload-improvement-error condition))))
    (setf dev-period-thread
          (devnet-start-dev-period-thread
           node
           shutdown-controller
           (lambda (condition)
             (setf dev-period-error condition))))
    (multiple-value-setq (dialer-thread dialer-sessions)
      (devnet-start-dial-scheduler-thread
       node
       shutdown-controller
       (lambda (condition)
         (setf dialer-error condition))))
    (setf sync-coordinator-thread
          (devnet-start-sync-coordinator-thread
           node shutdown-controller
           (lambda (condition)
             (setf sync-coordinator-error condition))))
    (setf discovery-thread
          (devnet-start-discovery-thread
           node
           shutdown-controller
           (lambda (condition)
             (setf discovery-error condition))))
    (setf discovery-server-thread
          (devnet-start-discovery-server-thread
           node
           shutdown-controller
           (lambda (condition)
             (setf discovery-server-error condition))))
    (multiple-value-setq (p2p-thread p2p-sessions)
      (devnet-start-p2p-listener-thread
       node
       p2p-listener
       shutdown-controller
       (lambda (condition)
         (setf p2p-error condition))))
    (let ((result nil)
          ;; Fixed by the first join that needs it, so every later join shares
          ;; what is left of it instead of adding a bound of its own.
          (join-deadline nil))
      (unwind-protect
           (setf result
                 (if public-listener
                     (let ((engine-thread
                             (sb-thread:make-thread
                              (lambda ()
                                (handler-case
                                    (setf engine-count
                                          (engine-rpc-http-service-serve-listener
                                           (devnet-node-service node)
                                           engine-listener
                                           :max-connections max-connections
                                           :concurrency http-concurrency
                                           :stop-p stop-requested-p))
                                  (serious-condition (condition)
                                    (setf engine-error condition)
                                    (devnet-shutdown-request
                                     shutdown-controller))))
                              :name "ethereum-lisp-devnet-engine-rpc")))
                       (handler-case
                           (setf public-count
                                 (engine-rpc-http-service-serve-listener
                                  (devnet-node-public-service node)
                                  public-listener
                                  :max-connections max-connections
                                  :concurrency http-concurrency
                                  :stop-p stop-requested-p))
                         (error (condition)
                           (setf public-error condition)
                           (devnet-shutdown-request shutdown-controller)))
                       ;; Give an in-flight Engine request a chance to complete
                       ;; after the public listener reaches its test limit.
                       ;; If the Engine listener still has fewer connections,
                       ;; shut both listeners down instead of waiting forever.
                       (when (eq :timeout
                                 (nth-value
                                  1 (sb-thread:join-thread
                                     engine-thread :timeout 1 :default nil)))
                         ;; A synthetic or broken accept backend may ignore
                         ;; listener closure.  Node shutdown must still be
                         ;; bounded once all registered sockets are closed, and
                         ;; this join shares the workers' deadline below.
                         (devnet-shutdown-request shutdown-controller)
                         (devnet-join-worker-by-deadline
                          engine-thread
                          (or join-deadline
                              (setf join-deadline
                                    (devnet-shutdown-join-deadline)))
                          "engine-rpc"))
                       (devnet-shutdown-request shutdown-controller)
                       (cond
                         (public-error (error public-error))
                         (engine-error (error engine-error))
                         (t
                          ;; A background-worker failure requests shutdown while
                          ;; Engine requests may still be draining.  If that
                          ;; listener exceeds the bounded join below, its thread
                          ;; is terminated before it can publish ENGINE-COUNT.
                          ;; Keep result construction total so the original
                          ;; worker condition is re-signalled after cleanup
                          ;; instead of being masked by (+ NIL PUBLIC-COUNT).
                          (let ((completed-engine-count (or engine-count 0)))
                            (list :engine-connections completed-engine-count
                                  :public-connections public-count
                                  :total-connections
                                  (+ completed-engine-count public-count))))))
                     (handler-case
                         (let ((engine-count
                                 (engine-rpc-http-service-serve-listener
                                  (devnet-node-service node)
                                  engine-listener
                                  :max-connections max-connections
                                  :concurrency http-concurrency
                                  :stop-p stop-requested-p)))
                           (devnet-shutdown-request shutdown-controller)
                           (list :engine-connections engine-count
                                 :public-connections 0
                                 :total-connections engine-count))
                       (error (condition)
                         (devnet-shutdown-request shutdown-controller)
                         (error condition)))))
        ;; Every worker join below shares ONE deadline. The supervisor's grace
        ;; period is a single budget, and per-join bounds that each look short
        ;; add up past it: the Hoodi stop that motivated this spent 15 s on the
        ;; coordinator alone and was SIGKILLed before the store close. A worker
        ;; that outlasts the deadline is terminated and abandoned, and the
        ;; shutdown goes on to the export and the store close regardless.
        ;;
        ;; The order is unchanged. The coordinator observes the stop at its
        ;; snap batch boundaries (*SNAP-SYNC-STOP-P*). Peer sockets are
        ;; registered closeables, so the shutdown request has already closed
        ;; them and the sessions unblock on their own. The outbound session
        ;; join belongs with the dialer, not the p2p arm: a node started with
        ;; --peer and no --port has no listener thread at all.
        (let ((deadline
                (or join-deadline
                    (setf join-deadline (devnet-shutdown-join-deadline)))))
          (flet ((join-worker (thread label)
                   (when thread
                     (devnet-shutdown-request shutdown-controller)
                     (devnet-join-worker-by-deadline thread deadline label)))
                 (join-sessions (sessions label)
                   (when sessions
                     (devnet-join-peer-sessions
                      sessions :deadline deadline :label label))))
            (join-worker rejournal-thread "rejournal")
            (join-worker txpool-maintenance-thread "txpool-maintenance")
            (join-worker payload-improvement-thread "payload-improvement")
            (join-worker dev-period-thread "dev-period")
            (join-worker sync-coordinator-thread "sync-coordinator")
            (join-worker dialer-thread "dialer")
            (join-sessions dialer-sessions "dialer-session")
            (join-worker discovery-thread "discovery")
            (join-worker discovery-server-thread "discovery-server")
            (join-worker p2p-thread "p2p-listener")
            (join-sessions p2p-sessions "p2p-session")
            (join-worker metrics-thread "metrics")
            (join-worker ws-thread "websocket")
            (join-sessions ws-sessions "websocket-session"))))
      (when ws-error
        (error ws-error))
      (when metrics-error
        (error metrics-error))
      (when p2p-error
        (error p2p-error))
      (when dialer-error
        (error dialer-error))
      (when sync-coordinator-error
        (error sync-coordinator-error))
      (when discovery-server-error
        (error discovery-server-error))
      (when rejournal-error
        (error rejournal-error))
      (when txpool-maintenance-error
        (error txpool-maintenance-error))
      (when payload-improvement-error
        (error payload-improvement-error))
      (when dev-period-error
        (error dev-period-error))

      (when discovery-error
        (error discovery-error))
      result)))

(defun start-devnet-node
    (node &key max-connections stop-p shutdown-controller
            install-signal-handlers-p signal-stream on-listeners-ready
            (public-rpc-enabled-p t))
  (unless (typep node 'devnet-node)
    (error "Devnet node must be devnet-node"))
  (when (and shutdown-controller
             (not (typep shutdown-controller 'devnet-shutdown-controller)))
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (when (and on-listeners-ready (not (functionp on-listeners-ready)))
    (error "Devnet listener-ready callback must be a function"))
  ;; Serving is the moment the Engine endpoint becomes reachable, so this is
  ;; where an unauthenticated non-loopback bind must be refused -- node
  ;; construction alone (e.g. --no-serve, which never listens) is not exposure.
  (devnet-cli-require-engine-authentication node)
  (let ((shutdown-controller
          (or shutdown-controller (make-devnet-shutdown-controller)))
        (engine-listener nil)
        (public-listener nil)
        (p2p-listener nil)
        (served-p nil))
    (unwind-protect
         (progn
           (setf engine-listener
                 (make-engine-rpc-http-socket-listener
                  (devnet-node-service node)))
           (devnet-shutdown-controller-register-listeners
            shutdown-controller engine-listener nil)
           (when public-rpc-enabled-p
             (setf public-listener
                   (make-engine-rpc-http-socket-listener
                    (devnet-node-public-service node))))
           (devnet-shutdown-controller-register-listeners
            shutdown-controller engine-listener public-listener)
           ;; Bound before the ready callback fires, so whatever reports the
           ;; node's endpoints can report a real p2p port rather than a promise.
           ;; No --port means no listener, which is the default.
           (when (devnet-node-p2p-port node)
             (setf p2p-listener
                   (make-eth-sync-socket-listener
                    :host (or (devnet-node-p2p-host node) "0.0.0.0")
                    :port (devnet-node-p2p-port node)))
             (setf (devnet-node-p2p-port node)
                   (eth-sync-listener-port p2p-listener))
             (devnet-shutdown-controller-add-closeable
              shutdown-controller
              (lambda () (eth-sync-listener-close p2p-listener))))
           (prog1
               (flet ((serve ()
                        (start-devnet-node-listeners
                         node
                         engine-listener
                         public-listener
                         :max-connections max-connections
                         :stop-p stop-p
                         :shutdown-controller shutdown-controller
                         :on-listeners-ready on-listeners-ready
                         :p2p-listener p2p-listener)))
                 (if install-signal-handlers-p
                     (call-with-devnet-shutdown-signal-handlers
                      shutdown-controller
                      #'serve
                      :stream (or signal-stream *error-output*))
                     (serve)))
             (setf served-p t)))
      (unless served-p
        (devnet-shutdown-request shutdown-controller)))))
