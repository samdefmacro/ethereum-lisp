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

(deftest eth-block-headers-and-bodies-round-trip-through-the-codecs
  (:layer :unit :module :p2p)
  ;; The exact server-side encode and client-side decode the socket fetch test
  ;; relies on, exercised offline so a codec error surfaces as a failure rather
  ;; than a hung read.
  (let* ((headers (list (eth-sync-test-header 1) (eth-sync-test-header 2)))
         (encoded (ethereum-lisp.eth-wire:encode-eth-block-headers 7 headers)))
    (multiple-value-bind (rid decoded)
        (ethereum-lisp.eth-wire:decode-eth-block-headers encoded)
      (is (= 7 rid))
      (is (equal '(1 2) (mapcar #'block-header-number decoded)))
      (is (bytes= (hash32-bytes (block-header-hash (first headers)))
                  (hash32-bytes (block-header-hash (first decoded)))))))
  (let* ((bodies (list (ethereum-lisp.eth-wire:make-eth-block-body
                        :transactions '()
                        :ommers (list (eth-sync-test-header 99)))))
         (encoded (ethereum-lisp.eth-wire:encode-eth-block-bodies 8 bodies)))
    (multiple-value-bind (rid decoded)
        (ethereum-lisp.eth-wire:decode-eth-block-bodies encoded)
      (is (= 8 rid))
      (is (= 99 (block-header-number
                 (first (ethereum-lisp.eth-wire:eth-block-body-ommers
                         (first decoded)))))))))

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

(defun eth-sync-test-header (number)
  "A well-formed pre-London block header with the given NUMBER, for exercising
the wire codecs (not a valid chain block). The hash-typed fields are left nil so
the encoder substitutes its zero/empty defaults."
  (make-block-header
   :difficulty 0
   :number number
   :gas-limit 30000000
   :gas-used 0
   :timestamp (+ 1600000000 number)
   :extra-data (make-byte-vector 0)))

(deftest eth-peer-downloads-headers-and-bodies-over-a-socket
  (:layer :integration :module :p2p :requires-local-sockets t)
  (let* ((config (eth-sync-test-config))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp)))
    (flet ((hello (client-id)
             (make-devp2p-hello
              :client-id client-id
              :capabilities (list (make-devp2p-capability "eth" 68))
              :node-id server-static-pub))
           (status ()
             (eth-build-status config *eth-sync-test-genesis* 3 0
                               *eth-sync-test-best* 0)))
      (setf (sb-bsd-sockets:sockopt-reuse-address listener) t)
      (unwind-protect
           (progn
             (sb-bsd-sockets:socket-bind
              listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
             (sb-bsd-sockets:socket-listen listener 1)
             (multiple-value-bind (address port)
                 (sb-bsd-sockets:socket-name listener)
               (declare (ignore address))
               (let ((server-error nil))
                 (let ((server-thread
                         (sb-thread:make-thread
                          (lambda ()
                            (handler-case
                                (let* ((client-socket
                                         (sb-bsd-sockets:socket-accept listener))
                                       (stream (p2p-binary-socket-stream client-socket))
                                       (connection (rlpx-accept-stream stream server-static))
                                       (peer (eth-peer-connect connection (hello "srv")
                                                               (status))))
                                  ;; Answer the header request: N headers from origin.
                                  (multiple-value-bind (id payload) (eth-peer-read peer)
                                    (declare (ignore id))
                                    (let* ((req (ethereum-lisp.eth-wire:decode-eth-get-block-headers
                                                 payload))
                                           (origin (ethereum-lisp.eth-wire:eth-get-block-headers-origin-number
                                                    req))
                                           (amount (ethereum-lisp.eth-wire:eth-get-block-headers-amount
                                                    req))
                                           (rid (ethereum-lisp.eth-wire:eth-get-block-headers-request-id
                                                 req))
                                           (headers (loop for n from origin
                                                          below (+ origin amount)
                                                          collect (eth-sync-test-header n))))
                                      (eth-peer-send peer
                                                     ethereum-lisp.eth-wire:+eth-message-block-headers+
                                                     (ethereum-lisp.eth-wire:encode-eth-block-headers
                                                      rid headers))))
                                  ;; Answer the body request: one body per hash,
                                  ;; each carrying a single ommer as a marker.
                                  (multiple-value-bind (id payload) (eth-peer-read peer)
                                    (declare (ignore id))
                                    (multiple-value-bind (rid hashes)
                                        (ethereum-lisp.eth-wire:decode-eth-get-block-bodies payload)
                                      (let ((bodies (mapcar
                                                     (lambda (h)
                                                       (declare (ignore h))
                                                       (ethereum-lisp.eth-wire:make-eth-block-body
                                                        :transactions '()
                                                        :ommers (list (eth-sync-test-header 99))))
                                                     hashes)))
                                        (eth-peer-send peer
                                                       ethereum-lisp.eth-wire:+eth-message-block-bodies+
                                                       (ethereum-lisp.eth-wire:encode-eth-block-bodies
                                                        rid bodies))))))
                              (error (condition) (setf server-error condition))))
                          :name "eth-fetch-test-server")))
                   (let ((client-socket (make-instance 'sb-bsd-sockets:inet-socket
                                                       :type :stream :protocol :tcp)))
                     (sb-bsd-sockets:socket-connect
                      client-socket (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
                     (let* ((stream (p2p-binary-socket-stream client-socket))
                            (connection (rlpx-connect-stream stream client-static
                                                             server-static-pub))
                            (peer (eth-peer-connect connection (hello "cli") (status))))
                       ;; Download three headers, numbered 1..3.
                       (let ((headers (eth-peer-get-block-headers
                                       peer :origin-number 1 :amount 3)))
                         (is (= 3 (length headers)))
                         (is (equal '(1 2 3) (mapcar #'block-header-number headers)))
                         ;; Download the bodies for those headers' hashes.
                         (let ((bodies (eth-peer-get-block-bodies
                                        peer (mapcar (lambda (h)
                                                       (hash32-bytes
                                                        (block-header-hash h)))
                                                     headers))))
                           (is (= 3 (length bodies)))
                           (is (= 99 (block-header-number
                                      (first (ethereum-lisp.eth-wire:eth-block-body-ommers
                                              (first bodies))))))))))
                   (sb-thread:join-thread server-thread)
                   (when server-error
                     (error "eth fetch server side failed: ~A" server-error))))))
        (ignore-errors (sb-bsd-sockets:socket-close listener))))))

(defun eth-sync-serve-chain (peer chain-length)
  "Answer eth header and body requests for a canned chain of CHAIN-LENGTH blocks
(numbered 1..CHAIN-LENGTH, empty bodies) until the peer disconnects."
  (handler-case
      (loop
        (multiple-value-bind (eth-id payload) (eth-peer-read peer)
          (cond
            ((= eth-id ethereum-lisp.eth-wire:+eth-message-get-block-headers+)
             (let* ((req (ethereum-lisp.eth-wire:decode-eth-get-block-headers payload))
                    (origin (ethereum-lisp.eth-wire:eth-get-block-headers-origin-number req))
                    (amount (ethereum-lisp.eth-wire:eth-get-block-headers-amount req))
                    (rid (ethereum-lisp.eth-wire:eth-get-block-headers-request-id req))
                    (headers (loop for n from origin below (+ origin amount)
                                   when (<= 1 n chain-length)
                                     collect (eth-sync-test-header n))))
               (eth-peer-send peer
                              ethereum-lisp.eth-wire:+eth-message-block-headers+
                              (ethereum-lisp.eth-wire:encode-eth-block-headers
                               rid headers))))
            ((= eth-id ethereum-lisp.eth-wire:+eth-message-get-block-bodies+)
             (multiple-value-bind (rid hashes)
                 (ethereum-lisp.eth-wire:decode-eth-get-block-bodies payload)
               (eth-peer-send peer
                              ethereum-lisp.eth-wire:+eth-message-block-bodies+
                              (ethereum-lisp.eth-wire:encode-eth-block-bodies
                               rid (mapcar
                                    (lambda (h)
                                      (declare (ignore h))
                                      (ethereum-lisp.eth-wire:make-eth-block-body
                                       :transactions '() :ommers '()))
                                    hashes))))))))
    (rlpx-disconnect () nil)))

(deftest eth-sync-downloads-a-chain-in-order-over-a-socket
  (:layer :integration :module :p2p :requires-local-sockets t)
  (let* ((config (eth-sync-test-config))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (chain-length 5)
         (imported '())
         (listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp)))
    (flet ((hello (client-id)
             (make-devp2p-hello
              :client-id client-id
              :capabilities (list (make-devp2p-capability "eth" 68))
              :node-id server-static-pub))
           (status ()
             (eth-build-status config *eth-sync-test-genesis* chain-length 0
                               *eth-sync-test-best* 0)))
      (setf (sb-bsd-sockets:sockopt-reuse-address listener) t)
      (unwind-protect
           (progn
             (sb-bsd-sockets:socket-bind
              listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
             (sb-bsd-sockets:socket-listen listener 1)
             (multiple-value-bind (address port)
                 (sb-bsd-sockets:socket-name listener)
               (declare (ignore address))
               (let ((server-error nil))
                 (let ((server-thread
                         (sb-thread:make-thread
                          (lambda ()
                            (handler-case
                                (let* ((client-socket
                                         (sb-bsd-sockets:socket-accept listener))
                                       (stream (p2p-binary-socket-stream client-socket))
                                       (connection (rlpx-accept-stream stream server-static))
                                       (peer (eth-peer-connect connection (hello "srv")
                                                               (status))))
                                  (eth-sync-serve-chain peer chain-length))
                              (error (condition) (setf server-error condition))))
                          :name "eth-sync-test-server")))
                   (let ((client-socket (make-instance 'sb-bsd-sockets:inet-socket
                                                       :type :stream :protocol :tcp)))
                     (sb-bsd-sockets:socket-connect
                      client-socket (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
                     (let* ((stream (p2p-binary-socket-stream client-socket))
                            (connection (rlpx-connect-stream stream client-static
                                                             server-static-pub))
                            (peer (eth-peer-connect connection (hello "cli") (status)))
                            ;; Download the whole chain two headers at a time.
                            (count (eth-sync-download-blocks
                                    peer
                                    (lambda (block)
                                      (push (block-header-number (block-header block))
                                            imported))
                                    :start-number 1 :batch-size 2)))
                       ;; Tell the server we are done so it stops serving.
                       (rlpx-send-disconnect connection +devp2p-message-disconnect+)
                       (is (= chain-length count))
                       ;; Blocks were imported in ascending order across batches.
                       (is (equal '(1 2 3 4 5) (nreverse imported)))))
                   (sb-thread:join-thread server-thread)
                   (when server-error
                     (error "eth sync server side failed: ~A" server-error))))))
        (ignore-errors (sb-bsd-sockets:socket-close listener))))))

(deftest eth-sync-connect-peer-dials-and-handshakes-over-a-socket
  (:layer :integration :module :p2p :requires-local-sockets t)
  (let* ((config (eth-sync-test-config))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (server-best
          (hex-to-bytes
           "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"))
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
             (let ((server-error nil))
               (let ((server-thread
                       (sb-thread:make-thread
                        (lambda ()
                          (handler-case
                              (let* ((client-socket
                                       (sb-bsd-sockets:socket-accept listener))
                                     (stream (p2p-binary-socket-stream client-socket))
                                     (connection (rlpx-accept-stream stream server-static)))
                                ;; The Status exchange completes inside
                                ;; eth-peer-connect on both sides, so the server
                                ;; needs nothing further.
                                (eth-peer-connect
                                 connection
                                 (make-devp2p-hello
                                  :client-id "srv"
                                  :capabilities (list (make-devp2p-capability "eth" 68))
                                  :node-id server-static-pub)
                                 (eth-build-status config *eth-sync-test-genesis*
                                                   7 0 server-best 0)))
                            (error (condition) (setf server-error condition))))
                        :name "eth-sync-dial-test-server")))
                 (multiple-value-bind (peer socket)
                     (eth-sync-connect-peer
                      "127.0.0.1" port server-static-pub client-static
                      (eth-build-status config *eth-sync-test-genesis* 3 0
                                        *eth-sync-test-best* 0)
                      :client-id "cli")
                   (unwind-protect
                        (progn
                          (is (= 16 (eth-peer-eth-offset peer)))
                          (is (bytes= server-static-pub
                                      (eth-peer-remote-public-key peer)))
                          (is (bytes= server-best
                                      (ethereum-lisp.eth-wire:eth-status-best-hash
                                       (eth-peer-remote-status peer)))))
                     (ignore-errors (sb-bsd-sockets:socket-close socket))))
                 (sb-thread:join-thread server-thread)
                 (when server-error
                   (error "eth sync dial server side failed: ~A" server-error))))))
      (ignore-errors (sb-bsd-sockets:socket-close listener)))))

;;;; End-to-end initial block download: produce real valid blocks on one store
;;;; and sync them into another store's state over a socket.

(defparameter *eth-sync-paris-genesis-json*
  ;; Post-merge (TTD 0), London active for base fee, pre-Shanghai so v1 empty
  ;; blocks (no withdrawals) validate. stateRoot omitted so it is derived from
  ;; the alloc consistently on both sides.
  "{\"config\":{\"chainId\":1337,\"terminalTotalDifficulty\":0,\"londonBlock\":0},\"nonce\":\"0x0\",\"timestamp\":\"0x0\",\"extraData\":\"0x\",\"gasLimit\":\"0x1c9c380\",\"difficulty\":\"0x0\",\"mixHash\":\"0x0000000000000000000000000000000000000000000000000000000000000000\",\"coinbase\":\"0x0000000000000000000000000000000000000000\",\"alloc\":{\"0x0000000000000000000000000000000000001001\":{\"balance\":\"0xde0b6b3a7640000\",\"nonce\":\"0x1\"}}}")

(defun eth-sync-make-seeded-store (genesis-json)
  "Return (VALUES STORE CONFIG GENESIS-BLOCK) for a fresh memory store seeded
with the genesis of GENESIS-JSON and its state available."
  (let* ((config (chain-config-from-genesis-json-string genesis-json))
         (state (state-db-from-genesis-json-string genesis-json))
         (genesis-block (genesis-block-from-state-genesis-json-string
                         genesis-json :config config))
         (store (make-engine-payload-memory-store)))
    (chain-store-put-block store genesis-block :state-available-p t)
    (commit-state-db-to-chain-store store (block-hash genesis-block) state)
    (values store config genesis-block)))

(defun eth-sync-produce-empty-blocks (genesis-block config count)
  "Chain COUNT valid empty post-merge blocks on top of GENESIS-BLOCK."
  (let ((parent genesis-block)
        (produced '()))
    (dotimes (i count (nreverse produced))
      (let* ((attrs (make-payload-attributes-v1
                     :timestamp (+ (block-header-timestamp (block-header parent)) 12)
                     :prev-randao (zero-hash32)
                     :suggested-fee-recipient (zero-address)))
             (block (ethereum-lisp.engine-payloads:engine-build-empty-payload
                     parent attrs config)))
        (push block produced)
        (setf parent block)))))

(defun eth-sync-serve-block-list (peer blocks)
  "Answer header and body requests for BLOCKS (a vector, block N at index N-1)
until the peer disconnects."
  (handler-case
      (loop
        (multiple-value-bind (eth-id payload) (eth-peer-read peer)
          (cond
            ((= eth-id ethereum-lisp.eth-wire:+eth-message-get-block-headers+)
             (let* ((req (ethereum-lisp.eth-wire:decode-eth-get-block-headers payload))
                    (origin (ethereum-lisp.eth-wire:eth-get-block-headers-origin-number req))
                    (amount (ethereum-lisp.eth-wire:eth-get-block-headers-amount req))
                    (rid (ethereum-lisp.eth-wire:eth-get-block-headers-request-id req))
                    (headers (loop for n from origin below (+ origin amount)
                                   when (<= 1 n (length blocks))
                                     collect (block-header (aref blocks (1- n))))))
               (eth-peer-send peer
                              ethereum-lisp.eth-wire:+eth-message-block-headers+
                              (ethereum-lisp.eth-wire:encode-eth-block-headers rid headers))))
            ((= eth-id ethereum-lisp.eth-wire:+eth-message-get-block-bodies+)
             (multiple-value-bind (rid hashes)
                 (ethereum-lisp.eth-wire:decode-eth-get-block-bodies payload)
               (eth-peer-send
                peer ethereum-lisp.eth-wire:+eth-message-block-bodies+
                (ethereum-lisp.eth-wire:encode-eth-block-bodies
                 rid (mapcar
                      (lambda (h)
                        (let ((block (find-if
                                      (lambda (b)
                                        (bytes= h (hash32-bytes (block-hash b))))
                                      blocks)))
                          (ethereum-lisp.eth-wire:make-eth-block-body
                           :transactions (block-transactions block)
                           :ommers (block-ommers block)
                           :withdrawals (block-withdrawals block)
                           :withdrawals-present-p (block-withdrawals-present-p block))))
                      hashes))))))))
    (rlpx-disconnect () nil)))

(deftest eth-sync-imports-produced-blocks-into-a-store-over-a-socket
  (:layer :integration :module :p2p :requires-local-sockets t)
  (multiple-value-bind (client-store config genesis-block)
      (eth-sync-make-seeded-store *eth-sync-paris-genesis-json*)
    (let* ((produced (coerce (eth-sync-produce-empty-blocks genesis-block config 3)
                             'vector))
           (genesis-hash (hash32-bytes (block-hash genesis-block)))
           ;; Store lookups key on hash32 objects; Status wants raw bytes.
           (tip-hash (block-hash (aref produced 2)))
           (server-static
            #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
           (client-static
            #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
           (server-static-pub (secp256k1-private-key-public-key server-static))
           (listener (make-instance 'sb-bsd-sockets:inet-socket
                                    :type :stream :protocol :tcp)))
      (flet ((hello (id)
               (make-devp2p-hello
                :client-id id
                :capabilities (list (make-devp2p-capability "eth" 68))
                :node-id server-static-pub))
             (status (head)
               (eth-build-status config genesis-hash head 0 genesis-hash 0)))
        (setf (sb-bsd-sockets:sockopt-reuse-address listener) t)
        (unwind-protect
             (progn
               (sb-bsd-sockets:socket-bind
                listener (sb-bsd-sockets:make-inet-address "127.0.0.1") 0)
               (sb-bsd-sockets:socket-listen listener 1)
               (multiple-value-bind (address port)
                   (sb-bsd-sockets:socket-name listener)
                 (declare (ignore address))
                 (let ((server-error nil))
                   (let ((server-thread
                           (sb-thread:make-thread
                            (lambda ()
                              (handler-case
                                  (let* ((client-socket
                                           (sb-bsd-sockets:socket-accept listener))
                                         (stream (p2p-binary-socket-stream client-socket))
                                         (connection (rlpx-accept-stream stream server-static))
                                         (peer (eth-peer-connect connection (hello "srv")
                                                                 (status 3))))
                                    (eth-sync-serve-block-list peer produced))
                                (error (condition) (setf server-error condition))))
                            :name "eth-sync-ibd-test-server")))
                     (let ((client-socket (make-instance 'sb-bsd-sockets:inet-socket
                                                         :type :stream :protocol :tcp)))
                       (sb-bsd-sockets:socket-connect
                        client-socket (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
                       (let* ((stream (p2p-binary-socket-stream client-socket))
                              (connection (rlpx-connect-stream stream client-static
                                                               server-static-pub))
                              (peer (eth-peer-connect connection (hello "cli") (status 0)))
                              (count (eth-sync-download-blocks
                                      peer
                                      (lambda (block)
                                        (execute-and-commit-engine-payload
                                         client-store block config))
                                      :start-number 1 :batch-size 2)))
                         (rlpx-send-disconnect connection +devp2p-message-disconnect+)
                         ;; All three produced blocks were downloaded and imported.
                         (is (= 3 count))
                         (is (not (null (chain-store-known-block client-store tip-hash))))
                         ;; Making the tip canonical advances the visible head to 3.
                         (chain-store-set-canonical-head
                          client-store tip-hash
                          :expected-chain-id (chain-config-chain-id config)
                          :chain-config config)
                         (is (= 3 (chain-store-head-number client-store)))))
                     (sb-thread:join-thread server-thread)
                     (when server-error
                       (error "eth sync IBD server side failed: ~A" server-error))))))
          (ignore-errors (sb-bsd-sockets:socket-close listener)))))))
