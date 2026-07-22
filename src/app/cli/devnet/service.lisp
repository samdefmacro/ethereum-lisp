(in-package #:ethereum-lisp.cli)

;;;; Devnet listener startup and service lifetime orchestration.

(defun start-devnet-node-listeners
    (node engine-listener public-listener
     &key max-connections stop-p shutdown-controller on-listeners-ready)
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
  #-sbcl
  (declare (ignore node engine-listener public-listener max-connections stop-p
                   shutdown-controller on-listeners-ready))
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
         (rejournal-error nil)
         (rejournal-thread nil)
         (dev-period-error nil)
         (dev-period-thread nil)
         (peer-sync-error nil)
         (peer-sync-thread nil)
         (discovery-error nil)
         (discovery-thread nil))
    (devnet-shutdown-controller-register-listeners
     shutdown-controller engine-listener public-listener)
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
    (setf dev-period-thread
          (devnet-start-dev-period-thread
           node
           shutdown-controller
           (lambda (condition)
             (setf dev-period-error condition))))
    (setf peer-sync-thread
          (devnet-start-peer-sync-thread
           node
           shutdown-controller
           (lambda (condition)
             (setf peer-sync-error condition))))
    (setf discovery-thread
          (devnet-start-discovery-thread
           node
           shutdown-controller
           (lambda (condition)
             (setf discovery-error condition))))
    (let ((result nil))
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
                                           :stop-p stop-requested-p))
                                  (error (condition)
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
                                  :stop-p stop-requested-p))
                         (error (condition)
                           (setf public-error condition)
                           (devnet-shutdown-request shutdown-controller)))
                       ;; Give an in-flight Engine request a chance to complete
                       ;; after the public listener reaches its test limit.
                       ;; If the Engine listener still has fewer connections,
                       ;; shut both listeners down instead of waiting forever.
                       (when (eq :timeout
                                 (sb-thread:join-thread
                                  engine-thread :timeout 1 :default :timeout))
                         (devnet-shutdown-request shutdown-controller)
                         (sb-thread:join-thread engine-thread))
                       (devnet-shutdown-request shutdown-controller)
                       (cond
                         (public-error (error public-error))
                         (engine-error (error engine-error))
                         (t
                          (list :engine-connections engine-count
                                :public-connections public-count
                                :total-connections
                                (+ engine-count public-count)))))
                     (handler-case
                         (let ((engine-count
                                 (engine-rpc-http-service-serve-listener
                                  (devnet-node-service node)
                                  engine-listener
                                  :max-connections max-connections
                                  :stop-p stop-requested-p)))
                           (devnet-shutdown-request shutdown-controller)
                           (list :engine-connections engine-count
                                 :public-connections 0
                                 :total-connections engine-count))
                       (error (condition)
                         (devnet-shutdown-request shutdown-controller)
                         (error condition)))))
        (when rejournal-thread
          (devnet-shutdown-request shutdown-controller)
          (sb-thread:join-thread rejournal-thread))
        (when dev-period-thread
          (devnet-shutdown-request shutdown-controller)
          (sb-thread:join-thread dev-period-thread))
        (when peer-sync-thread
          ;; The peer socket is not a registered listener, so a worker blocked
          ;; in a peer read will not wake from the shutdown request. Give it a
          ;; bounded join, then terminate if it is still stuck mid-sync.
          (devnet-shutdown-request shutdown-controller)
          (when (eq :timeout
                    (sb-thread:join-thread peer-sync-thread
                                           :timeout 5 :default :timeout))
            (ignore-errors (sb-thread:terminate-thread peer-sync-thread))
            (ignore-errors (sb-thread:join-thread peer-sync-thread))))
        (when discovery-thread
          ;; Same as peer-sync: a worker blocked in a UDP receive or a dial will
          ;; not wake from the shutdown request, so bound the join then terminate.
          (devnet-shutdown-request shutdown-controller)
          (when (eq :timeout
                    (sb-thread:join-thread discovery-thread
                                           :timeout 5 :default :timeout))
            (ignore-errors (sb-thread:terminate-thread discovery-thread))
            (ignore-errors (sb-thread:join-thread discovery-thread)))))
      (when rejournal-error
        (error rejournal-error))
      (when dev-period-error
        (error dev-period-error))
      (when peer-sync-error
        (error peer-sync-error))
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
  (let ((shutdown-controller
          (or shutdown-controller (make-devnet-shutdown-controller)))
        (engine-listener nil)
        (public-listener nil)
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
           (prog1
               (flet ((serve ()
                        (start-devnet-node-listeners
                         node
                         engine-listener
                         public-listener
                         :max-connections max-connections
                         :stop-p stop-p
                         :shutdown-controller shutdown-controller
                         :on-listeners-ready on-listeners-ready)))
                 (if install-signal-handlers-p
                     (call-with-devnet-shutdown-signal-handlers
                      shutdown-controller
                      #'serve
                      :stream (or signal-stream *error-output*))
                     (serve)))
             (setf served-p t)))
      (unless served-p
        (devnet-shutdown-request shutdown-controller)))))
