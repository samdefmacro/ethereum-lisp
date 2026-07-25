(in-package #:ethereum-lisp.test)

;;;; The inbound RLPx listener, and the recipient side of the handshake.
;;;;
;;;; Every socket-bearing test here binds port 0, closes everything on every
;;;; path, and joins with a timeout it then asserts on. The suite has no
;;;; per-test timeout outside the parallel e2e workers, so a test that can block
;;;; does not fail — it stops the whole run with no result at all.

(deftest eth-sync-listener-accepts-nothing-when-nobody-connects
  (:layer :unit :module :p2p :requires-local-sockets t)
  ;; The accept that underpins the whole wave: it must come back on its own
  ;; schedule rather than blocking until a peer happens to arrive, because that
  ;; is what lets an accept loop notice a shutdown request.
  (let ((listener (make-eth-sync-socket-listener :host "127.0.0.1" :port 0)))
    (unwind-protect
         (progn
           ;; Port 0 resolved to a real port, known before any peer connects.
           (is (plusp (eth-sync-listener-port listener)))
           (is (string= "127.0.0.1" (eth-sync-listener-endpoint-host listener)))
           (is (null (eth-sync-listener-accept listener :timeout-seconds 0.1)))
           (is (null (eth-sync-listener-accept listener :timeout-seconds 0.1))))
      (eth-sync-listener-close listener))))

(deftest eth-sync-listener-close-is-idempotent-and-final
  (:layer :unit :module :p2p :requires-local-sockets t)
  (let ((listener (make-eth-sync-socket-listener :host "127.0.0.1" :port 0)))
    (unwind-protect
         (progn
           (is (not (eth-sync-listener-closed-p listener)))
           (eth-sync-listener-close listener)
           (is (eth-sync-listener-closed-p listener))
           ;; Closing twice is not an error, and a closed listener accepts
           ;; nothing rather than erroring on a dead descriptor.
           (eth-sync-listener-close listener)
           (is (null (eth-sync-listener-accept listener :timeout-seconds 0.1))))
      (eth-sync-listener-close listener))))

(deftest eth-sync-listener-never-advertises-a-wildcard-address
  (:layer :unit :module :p2p)
  ;; A node bound to every interface still has to tell peers a dialable
  ;; address; 0.0.0.0 is not one.
  (is (string= "127.0.0.1" (eth-sync-socket-endpoint-host "0.0.0.0")))
  (is (string= "10.1.2.3" (eth-sync-socket-endpoint-host "10.1.2.3"))))

(deftest eth-sync-accept-peer-completes-the-handshake-from-a-dialer
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; The inbound half: our own listener accepts, and the recipient side of the
  ;; RLPx, Hello and Status handshake runs to completion against a real dialer.
  ;; Both sides end up with a peer that knows the other's identity.
  (let* ((config (eth-sync-test-config))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (client-static-pub (secp256k1-private-key-public-key client-static))
         (listener (make-eth-sync-socket-listener :host "127.0.0.1" :port 0))
         (server-result nil)
         (server-error nil))
    (flet ((status ()
             (eth-build-status config *eth-sync-test-genesis* 0 0
                               *eth-sync-test-best* 0)))
      (unwind-protect
           (let ((server-thread
                   (sb-thread:make-thread
                    (lambda ()
                      (handler-case
                          (multiple-value-bind (socket host port)
                              (eth-sync-listener-accept listener
                                                        :timeout-seconds 10)
                            (when socket
                              (unwind-protect
                                   (let ((peer (eth-sync-accept-peer
                                                socket server-static (status)
                                                :client-id "ethereum-lisp/inbound"
                                                :listen-port
                                                (eth-sync-listener-port listener))))
                                     (setf server-result
                                           (list :host host :port port
                                                 :remote-key
                                                 (eth-peer-remote-public-key peer)
                                                 :client-id
                                                 (eth-peer-remote-client-id peer)
                                                 :version
                                                 (eth-peer-eth-version peer))))
                                (ignore-errors
                                 (sb-bsd-sockets:socket-close socket)))))
                        (error (condition) (setf server-error condition))))
                    :name "eth-sync-accept-test-server")))
             (multiple-value-bind (peer socket)
                 (eth-sync-connect-peer "127.0.0.1"
                                        (eth-sync-listener-port listener)
                                        server-static-pub client-static (status)
                                        :client-id "ethereum-lisp/dialer"
                                        :listen-port 30399)
               (unwind-protect
                    (progn
                      ;; The dialer learned who answered, and what it listens on.
                      (is (bytes= server-static-pub
                                  (eth-peer-remote-public-key peer)))
                      (is (string= "ethereum-lisp/inbound"
                                   (eth-peer-remote-client-id peer)))
                      (is (= (eth-sync-listener-port listener)
                             (eth-peer-remote-listen-port peer))))
                 (ignore-errors (sb-bsd-sockets:socket-close socket))))
             (is (not (eq :timeout (sb-thread:join-thread server-thread
                                                          :timeout 15
                                                          :default :timeout))))
             (when server-error
               (error "inbound accept side failed: ~A" server-error))
             ;; And the acceptor learned the dialer's proven static key, its
             ;; client id, and where the connection came from.
             (is (not (null server-result)))
             (is (bytes= client-static-pub (getf server-result :remote-key)))
             (is (string= "ethereum-lisp/dialer" (getf server-result :client-id)))
             (is (string= "127.0.0.1" (getf server-result :host)))
             (is (plusp (getf server-result :port)))
             ;; Both sides negotiated the same eth version.
             (is (= 69 (getf server-result :version))))
        (eth-sync-listener-close listener)))))
