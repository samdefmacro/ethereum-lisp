(in-package #:ethereum-lisp.test)

;;;; The eth wire session: building and validating Status (offline) and the
;;;; full devp2p Hello + eth Status handshake run over a real loopback socket.

(defparameter *eth-sync-test-genesis*
  (hex-to-bytes
   "0xd4e56740f876aef8c010b86a40d5f56745a118d0906a34e69aec8c0db1cb8fa3"))

(defparameter *eth-sync-test-best*
  (hex-to-bytes
   "0x1111111111111111111111111111111111111111111111111111111111111111"))

(defun eth-sync-test-config ()
  (make-chain-config :chain-id 1
                     :homestead-block 1150000
                     :london-block 12965000
                     :shanghai-time 1681338455))

(deftest eth-build-status-carries-network-genesis-and-fork-id
  (:layer :unit :module :p2p)
  (let* ((config (eth-sync-test-config))
         (status (eth-build-status config *eth-sync-test-genesis*
                                   15000000 1690000000 *eth-sync-test-best* 12345)))
    (is (= 68 (ethereum-lisp.eth-wire:eth-status-version status)))
    ;; Network id defaults to the chain id.
    (is (= 1 (ethereum-lisp.eth-wire:eth-status-network-id status)))
    (is (= 12345 (ethereum-lisp.eth-wire:eth-status-total-difficulty status)))
    (is (bytes= *eth-sync-test-genesis*
                (ethereum-lisp.eth-wire:eth-status-genesis-hash status)))
    (is (bytes= *eth-sync-test-best*
                (ethereum-lisp.eth-wire:eth-status-best-hash status)))
    ;; The fork id is the config's fork id at this head.
    (let ((expected (ethereum-lisp.eth-wire:chain-config-eth-fork-id
                     config *eth-sync-test-genesis* 15000000 1690000000))
          (got (ethereum-lisp.eth-wire:eth-status-fork-id status)))
      (is (bytes= (ethereum-lisp.eth-wire:eth-fork-id-hash expected)
                  (ethereum-lisp.eth-wire:eth-fork-id-hash got)))
      (is (= (ethereum-lisp.eth-wire:eth-fork-id-next expected)
             (ethereum-lisp.eth-wire:eth-fork-id-next got))))
    ;; The network id can be overridden away from the chain id.
    (is (= 5 (ethereum-lisp.eth-wire:eth-status-network-id
              (eth-build-status config *eth-sync-test-genesis* 0 0
                                *eth-sync-test-best* 0 :network-id 5))))))

(deftest eth-status-validation-requires-matching-chain
  (:layer :unit :module :p2p)
  (let* ((config (eth-sync-test-config))
         (other-genesis
           (hex-to-bytes
            "0x2222222222222222222222222222222222222222222222222222222222222222"))
         (ours (eth-build-status config *eth-sync-test-genesis* 0 0
                                 *eth-sync-test-best* 0)))
    ;; The same chain is accepted.
    (is (eth-validate-peer-status
         ours (eth-build-status config *eth-sync-test-genesis* 0 0
                                *eth-sync-test-best* 0)))
    ;; A different genesis is rejected.
    (signals error
      (eth-validate-peer-status
       ours (eth-build-status config other-genesis 0 0 other-genesis 0)))
    ;; A different network is rejected.
    (signals error
      (eth-validate-peer-status
       ours (eth-build-status config *eth-sync-test-genesis* 0 0
                              *eth-sync-test-best* 0 :network-id 99)))))

(deftest eth-peer-handshake-completes-over-a-socket
  (:layer :integration :module :p2p :requires-local-sockets t)
  (let* ((config (eth-sync-test-config))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (client-static-pub (secp256k1-private-key-public-key client-static))
         (server-best
          (hex-to-bytes
           "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"))
         (listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp)))
    (flet ((hello (client-id node-id)
             (make-devp2p-hello
              :client-id client-id
              :capabilities (list (make-devp2p-capability "eth" 68))
              :node-id node-id)))
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
                                       (connection (rlpx-accept-stream stream server-static))
                                       (peer (eth-peer-connect
                                              connection
                                              (hello "ethereum-lisp/server"
                                                     server-static-pub)
                                              (eth-build-status
                                               config *eth-sync-test-genesis*
                                               100 0 server-best 999))))
                                  (setf server-result
                                        (list :remote (eth-peer-remote-public-key peer)
                                              :best (ethereum-lisp.eth-wire:eth-status-best-hash
                                                     (eth-peer-remote-status peer))
                                              :offset (eth-peer-eth-offset peer))))
                              (error (condition) (setf server-error condition))))
                          :name "eth-peer-test-server")))
                   (let ((client-socket (make-instance 'sb-bsd-sockets:inet-socket
                                                       :type :stream :protocol :tcp)))
                     (sb-bsd-sockets:socket-connect
                      client-socket (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
                     (let* ((stream (p2p-binary-socket-stream client-socket))
                            (connection (rlpx-connect-stream stream client-static
                                                             server-static-pub))
                            (peer (eth-peer-connect
                                   connection
                                   (hello "ethereum-lisp/client" client-static-pub)
                                   (eth-build-status config *eth-sync-test-genesis*
                                                     50 0 *eth-sync-test-best* 500))))
                       ;; The client sees the server's advertised head and eth at 0x10.
                       (is (bytes= server-best
                                   (ethereum-lisp.eth-wire:eth-status-best-hash
                                    (eth-peer-remote-status peer))))
                       (is (= 16 (eth-peer-eth-offset peer)))
                       (is (bytes= server-static-pub
                                   (eth-peer-remote-public-key peer)))))
                   (sb-thread:join-thread server-thread)
                   (when server-error
                     (error "eth peer server side failed: ~A" server-error))
                   ;; The server saw the client's static key, head, and eth offset.
                   (is (bytes= client-static-pub (getf server-result :remote)))
                   (is (bytes= *eth-sync-test-best* (getf server-result :best)))
                   (is (= 16 (getf server-result :offset)))))))
        (ignore-errors (sb-bsd-sockets:socket-close listener))))))
