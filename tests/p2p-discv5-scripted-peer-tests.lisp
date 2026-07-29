(in-package #:ethereum-lisp.test)

;;;; Scripted UDP peer coverage for the complete discv5.1 handshake.
;;;;
;;;; The peer intentionally starts without session keys, challenges the random
;;;; packet, verifies the identity proof and ENR, derives flipped session keys,
;;;; then returns an encrypted PONG. Any unhandled serious condition in the
;;;; server thread would terminate the whole --script test process, so the body
;;;; has the mandatory SERIOUS-CONDITION backstop.

(defun discv5-test-ipv4-string (ip)
  (format nil "~D.~D.~D.~D"
          (aref ip 0) (aref ip 1) (aref ip 2) (aref ip 3)))

(deftest discv5-scripted-peer-completes-handshake-and-ping
  (:layer :integration :module :p2p :requires-local-sockets t)
  (let ((client-key
          #xeef77acb6c6a6eebc5b363a475ac583ec7eccdb42b6481424c60f59aa326547f)
        (server-key
          #x66fb62bfbd66b9177a138c1e5cddbe4f7c30c343e94e68df8769459cb1cde628)
        (server-condition nil))
    (multiple-value-bind (server-socket server-port)
        (ethereum-lisp.discv5:discv5-make-socket
         :host "127.0.0.1" :port 0)
      (multiple-value-bind (client-socket client-port)
          (ethereum-lisp.discv5:discv5-make-socket
           :host "127.0.0.1" :port 0)
        (let* ((client-record
                 (discv5-test-record
                  client-key 3 #(127 0 0 1) client-port))
               (server-record
                 (discv5-test-record
                  server-key 7 #(127 0 0 1) server-port))
               (client-codec
                 (ethereum-lisp.discv5:make-discv5-codec
                  client-key client-record))
               (server-codec
                 (ethereum-lisp.discv5:make-discv5-codec
                  server-key server-record))
               (server-table
                 (ethereum-lisp.discv5:make-discv5-routing-table
                  server-record))
               (thread
                 (sb-thread:make-thread
                  (lambda ()
                    (handler-case
                        (multiple-value-bind
                              (probe source-ip source-port)
                            (ethereum-lisp.discv5:discv5-receive
                             server-socket 5)
                          (unless probe
                            (error "scripted peer did not receive random packet"))
                          (let* ((source-host
                                   (discv5-test-ipv4-string source-ip))
                                 (source-endpoint
                                   (format nil "~A:~D" source-host source-port)))
                            (multiple-value-bind (kind nonce source-id)
                                (ethereum-lisp.discv5:discv5-decode-packet
                                 server-codec probe source-endpoint)
                              (unless (eq kind :unknown)
                                (error "scripted peer expected random packet"))
                              (ethereum-lisp.discv5:discv5-send-to
                               server-socket
                               (ethereum-lisp.discv5:discv5-encode-whoareyou-packet
                                server-codec source-id source-endpoint nonce
                                :record-seq 0)
                               source-host source-port))
                            (multiple-value-bind
                                  (handshake handshake-ip handshake-port)
                                (ethereum-lisp.discv5:discv5-receive
                                 server-socket 5)
                              (unless handshake
                                (error "scripted peer did not receive handshake"))
                              (unless (and (= handshake-port source-port)
                                           (equalp handshake-ip source-ip))
                                (error "scripted peer handshake endpoint changed"))
                              (multiple-value-bind (kind request source-id aux)
                                  (ethereum-lisp.discv5:discv5-decode-packet
                                   server-codec handshake source-endpoint)
                                (unless (and (eq kind :message)
                                             (eq aux :handshake)
                                             (typep request
                                                    'ethereum-lisp.discv5:discv5-ping))
                                  (error "scripted peer expected handshake PING"))
                                ;; Authentication validates the observed endpoint
                                ;; before it enters the routing table.
                                (ethereum-lisp.discv5:discv5-routing-table-put-record
                                 server-table client-record
                                 :host source-ip :port source-port
                                 :validated-p t :now 100)
                                (multiple-value-bind (responses stale-p)
                                    (ethereum-lisp.discv5:discv5-serve-message
                                     server-table request source-id
                                     source-ip source-port :now 100)
                                  (declare (ignore stale-p))
                                  (dolist (response responses)
                                    (ethereum-lisp.discv5:discv5-send-to
                                     server-socket
                                     (ethereum-lisp.discv5:discv5-encode-message-packet
                                      server-codec source-id source-endpoint
                                      response)
                                     source-host source-port)))))))
                      (serious-condition (condition)
                        (setf server-condition condition))))
                  :name "discv5-scripted-peer")))
          (unwind-protect
               (let ((response
                       (ethereum-lisp.discv5:discv5-exchange
                        client-codec server-record "127.0.0.1" server-port
                        (ethereum-lisp.discv5:make-discv5-ping
                         :request-id #(1 2 3 4) :enr-seq 3)
                        :socket client-socket :timeout-seconds 5)))
                 (sb-thread:join-thread thread)
                 (when server-condition
                   (error "scripted discv5 peer failed: ~A" server-condition))
                 (is (typep response 'ethereum-lisp.discv5:discv5-pong))
                 (when response
                   (is (equalp #(1 2 3 4)
                               (ethereum-lisp.discv5:discv5-pong-request-id
                                response)))
                   (is (= 7
                          (ethereum-lisp.discv5:discv5-pong-enr-seq
                           response)))
                   (is (= client-port
                          (ethereum-lisp.discv5:discv5-pong-recipient-port
                           response))))
                 ;; Both sides retained opposite read/write keys.
                 (let* ((client-endpoint
                          (format nil "127.0.0.1:~D" server-port))
                        (server-endpoint
                          (format nil "127.0.0.1:~D" client-port))
                        (client-session
                          (ethereum-lisp.discv5:discv5-codec-session
                           client-codec
                           (ethereum-lisp.discv5:discv5-codec-node-id
                            server-codec)
                           client-endpoint))
                        (server-session
                          (ethereum-lisp.discv5:discv5-codec-session
                           server-codec
                           (ethereum-lisp.discv5:discv5-codec-node-id
                            client-codec)
                           server-endpoint)))
                   (is (not (null client-session)))
                   (is (not (null server-session)))
                   (when (and client-session server-session)
                     (is (bytes=
                          (ethereum-lisp.discv5:discv5-session-write-key
                           client-session)
                          (ethereum-lisp.discv5:discv5-session-read-key
                           server-session)))
                     (is (bytes=
                          (ethereum-lisp.discv5:discv5-session-read-key
                           client-session)
                          (ethereum-lisp.discv5:discv5-session-write-key
                           server-session))))))
            (ignore-errors (sb-bsd-sockets:socket-close client-socket))
            (ignore-errors (sb-bsd-sockets:socket-close server-socket))))))))
