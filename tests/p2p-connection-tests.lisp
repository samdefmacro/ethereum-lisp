(in-package #:ethereum-lisp.test)

;;;; The RLPx protocol run over a real loopback TCP socket: two threads complete
;;;; the handshake and exchange a Hello, the way two nodes would.

(defun p2p-binary-socket-stream (socket)
  (sb-bsd-sockets:socket-make-stream
   socket :input t :output t
          :element-type '(unsigned-byte 8) :buffering :full))

(deftest rlpx-connection-completes-over-a-socket
  (:layer :integration :module :p2p :requires-local-sockets t)
  (let* ((server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (client-static-pub (secp256k1-private-key-public-key client-static))
         (listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp)))
    (setf (sb-bsd-sockets:sockopt-reuse-address listener) t)
    (unwind-protect
         (progn
           (sb-bsd-sockets:socket-bind
            listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
           (sb-bsd-sockets:socket-listen listener 1)
           (multiple-value-bind (address port)
               (sb-bsd-sockets:socket-name listener)
             (declare (ignore address))
             (let ((server-result nil)
                   (server-error nil))
               (let ((server-thread
                       (sb-thread:make-thread
                        (lambda ()
                          (handler-case
                              (let* ((client-socket
                                       (sb-bsd-sockets:socket-accept listener))
                                     (stream (p2p-binary-socket-stream client-socket))
                                     (connection (rlpx-accept-stream stream server-static)))
                                (multiple-value-bind (code payload)
                                    (rlpx-connection-read-message connection
                                                                  :compressed nil)
                                  (setf server-result
                                        (list :code code
                                              :client-id
                                              (devp2p-hello-client-id
                                               (decode-devp2p-hello payload))
                                              :remote
                                              (rlpx-connection-remote-public-key
                                               connection)))))
                            (error (condition) (setf server-error condition))))
                        :name "rlpx-test-server")))
                 (let ((client-socket (make-instance 'sb-bsd-sockets:inet-socket
                                                     :type :stream :protocol :tcp)))
                   (sb-bsd-sockets:socket-connect
                    client-socket (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
                   (let* ((stream (p2p-binary-socket-stream client-socket))
                          (connection (rlpx-connect-stream stream client-static
                                                           server-static-pub)))
                     ;; The client learns the server's static key from the parameter.
                     (is (bytes= server-static-pub
                                 (rlpx-connection-remote-public-key connection)))
                     (rlpx-connection-write-message
                      connection +devp2p-message-hello+
                      (encode-devp2p-hello
                       (make-devp2p-hello :client-id "ethereum-lisp/client"
                                          :capabilities '()
                                          :node-id client-static-pub))
                      :compressed nil)))
                 (sb-thread:join-thread server-thread)
                 (when server-error
                   (error "RLPx server side failed: ~A" server-error))
                 (is (= +devp2p-message-hello+ (getf server-result :code)))
                 (is (string= "ethereum-lisp/client" (getf server-result :client-id)))
                 ;; The server recovered the client's static key from the handshake.
                 (is (bytes= client-static-pub (getf server-result :remote)))))))
      (ignore-errors (sb-bsd-sockets:socket-close listener)))))
