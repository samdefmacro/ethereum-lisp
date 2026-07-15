(in-package #:ethereum-lisp.rpc-http)

(defun make-engine-rpc-http-connection
    (&key input-stream output-stream (close-function (lambda () nil)))
  (unless (input-stream-p input-stream)
    (block-validation-fail
     "Engine RPC HTTP connection input stream must be readable"))
  (unless (output-stream-p output-stream)
    (block-validation-fail
     "Engine RPC HTTP connection output stream must be writable"))
  (unless (functionp close-function)
    (block-validation-fail
     "Engine RPC HTTP connection close function must be a function"))
  (%make-engine-rpc-http-connection
   :input-stream input-stream
   :output-stream output-stream
   :close-function close-function))

(defun make-engine-rpc-http-listener
    (&key endpoint accept-function (close-function (lambda () nil)))
  (unless (stringp endpoint)
    (block-validation-fail "Engine RPC HTTP listener endpoint must be a string"))
  (unless (functionp accept-function)
    (block-validation-fail
     "Engine RPC HTTP listener accept function must be a function"))
  (unless (functionp close-function)
    (block-validation-fail
     "Engine RPC HTTP listener close function must be a function"))
  (%make-engine-rpc-http-listener
   :endpoint endpoint
   :accept-function accept-function
   :close-function close-function))

(defun engine-rpc-http-listener-accept (listener)
  (unless (typep listener 'engine-rpc-http-listener)
    (block-validation-fail
     "Engine RPC HTTP listener must be engine-rpc-http-listener"))
  (let ((connection
          (funcall (engine-rpc-http-listener-accept-function listener))))
    (when connection
      (unless (typep connection 'engine-rpc-http-connection)
        (block-validation-fail
         "Engine RPC HTTP listener accept function returned non-connection")))
    connection))

(defun engine-rpc-http-connection-close (connection)
  (unless (typep connection 'engine-rpc-http-connection)
    (block-validation-fail
     "Engine RPC HTTP connection must be engine-rpc-http-connection"))
  (funcall (engine-rpc-http-connection-close-function connection)))

(defun engine-rpc-http-listener-close (listener)
  (unless (typep listener 'engine-rpc-http-listener)
    (block-validation-fail
     "Engine RPC HTTP listener must be engine-rpc-http-listener"))
  (funcall (engine-rpc-http-listener-close-function listener)))

(defun engine-rpc-http-socket-host (host)
  (if (string= host "localhost")
      "127.0.0.1"
      host))

(defun engine-rpc-http-socket-endpoint-host (host)
  (if (string= host "0.0.0.0")
      "127.0.0.1"
      host))

(defun make-engine-rpc-http-socket-listener
    (service &key (backlog 16))
  (unless (typep service 'engine-rpc-http-service)
    (block-validation-fail
     "Engine RPC HTTP service must be engine-rpc-http-service"))
  (unless (and (integerp backlog) (plusp backlog))
    (block-validation-fail
     "Engine RPC HTTP socket backlog must be positive"))
  #-sbcl
  (declare (ignore service backlog))
  #-sbcl
  (block-validation-fail
   "Engine RPC HTTP socket listener requires SBCL sb-bsd-sockets")
  #+sbcl
  (let* ((host (engine-rpc-http-socket-host
                (engine-rpc-http-service-host service)))
         (socket (make-instance 'sb-bsd-sockets:inet-socket
                                :type :stream
                                :protocol :tcp))
         (close-lock
           (sb-thread:make-mutex
            :name "ethereum-lisp-rpc-http-listener-close"))
         (closed-p nil))
    (setf (sb-bsd-sockets:sockopt-reuse-address socket) t)
    (handler-case
        (progn
          (sb-bsd-sockets:socket-bind
           socket
           (sb-bsd-sockets:make-inet-address host)
           (engine-rpc-http-service-port service))
          (sb-bsd-sockets:socket-listen socket backlog)
          (multiple-value-bind (address port)
              (sb-bsd-sockets:socket-name socket)
            (declare (ignore address))
            (make-engine-rpc-http-listener
             :endpoint (format nil "~A:~D"
                               (engine-rpc-http-socket-endpoint-host host)
                               port)
             :accept-function
             (lambda ()
               (multiple-value-bind (client-socket peer-address peer-port)
                   (sb-bsd-sockets:socket-accept socket)
                 (declare (ignore peer-address peer-port))
                 (let ((stream
                         (sb-bsd-sockets:socket-make-stream
                          client-socket
                          :input t
                          :output t
                          :element-type 'character
                          :external-format :utf-8
                          :buffering :none)))
                   (make-engine-rpc-http-connection
                    :input-stream stream
                    :output-stream stream
                    :close-function (lambda () (close stream))))))
             :close-function
             (lambda ()
               (sb-thread:with-mutex (close-lock)
                 (unless closed-p
                   (setf closed-p t)
                   ;; On Linux, closing a listening descriptor from another
                   ;; thread does not reliably wake a blocking accept(2).
                   ;; shutdown(2) first so service shutdown can join the
                   ;; listener thread without waiting for another client.
                   (ignore-errors
                     (sb-bsd-sockets:socket-shutdown
                      socket :direction :io))
                   (sb-bsd-sockets:socket-close socket)))))))
      (error (condition)
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        (error condition)))))
