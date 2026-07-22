(in-package #:ethereum-lisp.test)

;;;; The devp2p session handshake: capability negotiation (offline) and the
;;;; Hello exchange run over a real loopback socket.

(deftest rlpx-negotiates-a-single-shared-eth-capability
  (:layer :unit :module :p2p)
  (let ((shared (rlpx-negotiate-capabilities
                 (list (make-devp2p-capability "eth" 68))
                 (list (make-devp2p-capability "eth" 68)
                       (make-devp2p-capability "snap" 1)))))
    (is (= 1 (length shared)))
    (let ((eth (rlpx-shared-capability-named shared "eth")))
      (is (not (null eth)))
      (is (= 68 (rlpx-shared-capability-version eth)))
      ;; The first shared capability's ids start right after the 16 base ids.
      (is (= 16 (rlpx-shared-capability-offset eth))))
    ;; snap is not shared: we did not advertise it.
    (is (null (rlpx-shared-capability-named shared "snap")))))

(deftest rlpx-picks-the-highest-common-capability-version
  (:layer :unit :module :p2p)
  (let ((shared (rlpx-negotiate-capabilities
                 (list (make-devp2p-capability "eth" 67)
                       (make-devp2p-capability "eth" 68))
                 (list (make-devp2p-capability "eth" 66)
                       (make-devp2p-capability "eth" 68)))))
    (is (= 68 (rlpx-shared-capability-version
               (rlpx-shared-capability-named shared "eth"))))))

(deftest rlpx-shares-nothing-without-a-common-capability
  (:layer :unit :module :p2p)
  (is (null (rlpx-negotiate-capabilities
             (list (make-devp2p-capability "eth" 68))
             (list (make-devp2p-capability "les" 4))))))

(deftest rlpx-assigns-contiguous-message-blocks-in-name-order
  (:layer :unit :module :p2p)
  ;; With two shared capabilities the second's block starts after the first's.
  (let ((ethereum-lisp.p2p::+devp2p-capability-message-counts+
          '(("aaa" . 8) ("eth" . 17))))
    (let ((shared (rlpx-negotiate-capabilities
                   (list (make-devp2p-capability "eth" 68)
                         (make-devp2p-capability "aaa" 1))
                   (list (make-devp2p-capability "eth" 68)
                         (make-devp2p-capability "aaa" 1)))))
      ;; aaa sorts first, so it takes the block at 16.
      (is (= 16 (rlpx-shared-capability-offset
                 (rlpx-shared-capability-named shared "aaa"))))
      ;; eth follows, starting at 16 + aaa's 8 ids.
      (is (= 24 (rlpx-shared-capability-offset
                 (rlpx-shared-capability-named shared "eth")))))))

(deftest rlpx-hello-exchange-negotiates-eth-over-a-socket
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
                                (multiple-value-bind (peer shared)
                                    (rlpx-exchange-hello
                                     connection
                                     (make-devp2p-hello
                                      :client-id "ethereum-lisp/server"
                                      :capabilities
                                      (list (make-devp2p-capability "eth" 68))
                                      :node-id server-static-pub))
                                  (setf server-result
                                        (list :client-id (devp2p-hello-client-id peer)
                                              :eth-offset
                                              (rlpx-shared-capability-offset
                                               (rlpx-shared-capability-named
                                                shared "eth"))))))
                            (error (condition) (setf server-error condition))))
                        :name "rlpx-hello-test-server")))
                 (let ((client-socket (make-instance 'sb-bsd-sockets:inet-socket
                                                     :type :stream :protocol :tcp)))
                   (sb-bsd-sockets:socket-connect
                    client-socket (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
                   (let* ((stream (p2p-binary-socket-stream client-socket))
                          (connection (rlpx-connect-stream stream client-static
                                                           server-static-pub)))
                     (multiple-value-bind (peer shared)
                         (rlpx-exchange-hello
                          connection
                          (make-devp2p-hello
                           :client-id "ethereum-lisp/client"
                           :capabilities (list (make-devp2p-capability "eth" 68)
                                               (make-devp2p-capability "snap" 1))
                           :node-id client-static-pub))
                       ;; The client sees the server's Hello and shares eth at 0x10.
                       (is (string= "ethereum-lisp/server"
                                    (devp2p-hello-client-id peer)))
                       (is (= 16 (rlpx-shared-capability-offset
                                  (rlpx-shared-capability-named shared "eth")))))))
                 (sb-thread:join-thread server-thread)
                 (when server-error
                   (error "RLPx server side failed: ~A" server-error))
                 ;; The server likewise negotiated eth at 0x10 and read our id.
                 (is (string= "ethereum-lisp/client"
                              (getf server-result :client-id)))
                 (is (= 16 (getf server-result :eth-offset)))))))
      (ignore-errors (sb-bsd-sockets:socket-close listener)))))
