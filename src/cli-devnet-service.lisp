(in-package #:ethereum-lisp.cli)

(defun devnet-start-rejournal-thread
    (node shutdown-controller error-callback)
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (let ((state
          (make-devnet-rejournal-state
           node
           (devnet-node-txpool-rejournal-seconds node))))
    (when (devnet-rejournal-state-enabled-p state)
      (sb-thread:make-thread
       (lambda ()
         (handler-case
             (loop until (devnet-shutdown-requested-p shutdown-controller)
                   do (sleep 1)
                      (unless (devnet-shutdown-requested-p
                               shutdown-controller)
                        (devnet-rejournal-state-tick state)))
           (error (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-txpool-rejournal"))))

(defun devnet-start-dev-period-thread
    (node shutdown-controller error-callback)
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (let ((state
          (make-devnet-dev-period-state
           node
           (devnet-node-dev-period-seconds node))))
    (when (devnet-dev-period-state-enabled-p state)
      (sb-thread:make-thread
       (lambda ()
         (handler-case
             (loop until (devnet-shutdown-requested-p shutdown-controller)
                   do (sleep 1)
                      (unless (devnet-shutdown-requested-p
                               shutdown-controller)
                        (devnet-dev-period-state-tick state)))
           (error (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-dev-period"))))

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
         (dev-period-thread nil))
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
                       (when public-count
                         (devnet-shutdown-request shutdown-controller))
                       (sb-thread:join-thread engine-thread)
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
          (sb-thread:join-thread dev-period-thread)))
      (when rejournal-error
        (error rejournal-error))
      (when dev-period-error
        (error dev-period-error))
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
