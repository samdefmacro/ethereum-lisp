(in-package #:ethereum-lisp.core)

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
    (block-validation-fail "Engine RPC HTTP socket backlog must be positive"))
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
                                :protocol :tcp)))
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
               (sb-bsd-sockets:socket-close socket)))))
      (error (condition)
        (ignore-errors (sb-bsd-sockets:socket-close socket))
        (error condition)))))
