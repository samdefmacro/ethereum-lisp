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

(deftest eth-chain-context-judges-a-node-record
  (:layer :unit :module :p2p)
  ;; What discovery uses to decide whether a node is worth dialing, and what a
  ;; node publishes so others can decide the same about it. The two are checked
  ;; together because they have to agree: a client that filters on an entry it
  ;; does not itself publish gets filtered straight back out.
  (let* ((config (eth-sync-test-config))
         (context (make-eth-chain-context config *eth-sync-test-genesis*
                                          15000000 1690000000))
         (ours (cdr (assoc "eth" (eth-chain-context-record-pairs context)
                           :test #'string=))))
    ;; Our own advertised entry is one we would accept.
    (is (eth-chain-context-record-compatible-p context ours))
    ;; A peer one fork behind us, announcing the fork it has not yet crossed,
    ;; is compatible -- EIP-2124 rule 2, and the ordinary case of a peer that
    ;; has not upgraded yet.
    (is (eth-chain-context-record-compatible-p
         context
         (ethereum-lisp.eth-wire:eth-fork-id-enr-entry
          (ethereum-lisp.eth-wire:chain-config-eth-fork-id
           config *eth-sync-test-genesis* 12000000 0))))
    ;; A fork hash from another chain is not.
    (is (not (eth-chain-context-record-compatible-p
              context
              (ethereum-lisp.eth-wire:eth-fork-id-enr-entry
               (ethereum-lisp.eth-wire:make-eth-fork-id
                (hex-to-bytes "0xdeadbeef") 0)))))
    ;; And neither is a node that says nothing about its chain. On a shared DHT
    ;; `I cannot tell' has to mean `not mine', or the filter admits precisely
    ;; the nodes it exists to exclude.
    (is (not (eth-chain-context-record-compatible-p context nil)))
    (is (not (eth-chain-context-record-compatible-p
              context (hex-to-bytes "0xdeadbeef"))))))

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

(defun eth-sync-test-header (number &optional parent-hash)
  "A well-formed pre-London block header with the given NUMBER, for exercising
the wire codecs (not a valid chain block). The hash-typed fields are left nil so
the encoder substitutes its zero/empty defaults."
  (make-block-header
   :parent-hash parent-hash
   :difficulty 0
   :number number
   :gas-limit 30000000
   :gas-used 0
   :timestamp (+ 1600000000 number)
   :extra-data (make-byte-vector 0)))

(defun eth-sync-test-chain-headers (length)
  (loop with parent = nil
        for number from 1 to length
        for header = (eth-sync-test-header number parent)
        collect header
        do (setf parent (block-header-hash header))))

(deftest eth-sync-resume-anchor-rejects-a-different-first-parent
  (:layer :unit :module :p2p)
  (let* ((durable-parent
           (make-hash32
            (hex-to-bytes
             "0x1111111111111111111111111111111111111111111111111111111111111111")))
         (other-parent
           (make-hash32
            (hex-to-bytes
             "0x2222222222222222222222222222222222222222222222222222222222222222")))
         (matching (eth-sync-test-header 9 durable-parent))
         (divergent (eth-sync-test-header 9 other-parent)))
    (is (eth-sync-validate-header-batch
         (list matching) 9 nil :expected-parent-hash durable-parent))
    (signals error
      (eth-sync-validate-header-batch
       (list divergent) 9 nil :expected-parent-hash durable-parent))))

(deftest eth-sync-validates-delivered-header-and-body-commitments
  (:layer :unit :module :p2p)
  (let* ((headers (eth-sync-test-chain-headers 3))
         (empty-body
           (ethereum-lisp.eth-wire:make-eth-block-body
            :transactions '() :ommers '()))
         (committed-header
           (make-block-header
            :number 1 :difficulty 0 :gas-limit 30000000
            :extra-data (make-byte-vector 0)
            :transactions-root (transaction-list-root '())
            :ommers-hash (ommers-hash '()))))
    (is (eth-sync-validate-header-batch headers 1 nil))
    (is (eth-sync-validate-header-batch
         (rest headers) 2 (first headers)))
    (signals error
      (eth-sync-validate-header-batch headers 2 nil))
    (let ((broken (copy-list headers)))
      (setf (block-header-parent-hash (second broken)) (zero-hash32))
      (signals error
        (eth-sync-validate-header-batch broken 1 nil)))
    (is (eth-sync-validate-body committed-header empty-body))
    (signals error
      (eth-sync-validate-body
       committed-header
       (ethereum-lisp.eth-wire:make-eth-block-body
        :transactions (list (make-legacy-transaction
                             :nonce 1 :gas-price 2 :gas-limit 21000
                             :value 3 :v 27 :r 4 :s 5))
        :ommers '())))))

(deftest eth-sync-backfill-classifies-only-peer-body-failures
  (:layer :unit :module :p2p)
  (let* ((header
           (make-block-header
            :number 1 :difficulty 0 :gas-limit 30000000
            :extra-data (make-byte-vector 0)
            :transactions-root (transaction-list-root '())
            :ommers-hash (ommers-hash '())))
         (empty-body
           (ethereum-lisp.eth-wire:make-eth-block-body
            :transactions '() :ommers '()))
         (wrong-body
           (ethereum-lisp.eth-wire:make-eth-block-body
            :transactions
            (list (make-legacy-transaction
                   :nonce 1 :gas-price 2 :gas-limit 21000
                   :value 3 :v 27 :r 4 :s 5))
            :ommers '()))
         (fetch-symbol
           'ethereum-lisp.eth-sync:eth-peer-get-block-bodies)
         (original-fetch (fdefinition fetch-symbol))
         (import-calls 0))
    (unwind-protect
         (progn
           (setf (fdefinition fetch-symbol)
                 (lambda (peer hashes)
                   (declare (ignore peer hashes))
                   (list wrong-body)))
           (signals ethereum-lisp.eth-sync:eth-sync-backfill-peer-error
             (ethereum-lisp.eth-sync:eth-sync-import-headers-with-bodies
              nil (list header)
              (lambda (block)
                (declare (ignore block))
                (incf import-calls))))
           (is (= 0 import-calls))
           ;; Positive control: the same shipped entry point reaches import
           ;; once the peer supplies the committed body.
           (setf (fdefinition fetch-symbol)
                 (lambda (peer hashes)
                   (declare (ignore peer hashes))
                   (list empty-body)))
           (is (= 1
                  (ethereum-lisp.eth-sync:eth-sync-import-headers-with-bodies
                   nil (list header)
                   (lambda (block)
                     (declare (ignore block))
                     (incf import-calls)))))
           (is (= 1 import-calls))
           ;; IMPORT-BLOCK is outside peer-error classification.  A local
           ;; durable failure must remain a storage error for the supervisor.
           (signals ethereum-lisp.validation:storage-error
             (ethereum-lisp.eth-sync:eth-sync-import-headers-with-bodies
              nil (list header)
              (lambda (block)
                (declare (ignore block))
                (error 'ethereum-lisp.validation:storage-error
                       :message "Injected backfill storage failure"))))
           ;; Even a validation-shaped failure from IMPORT-BLOCK is local to
           ;; the callback and must not be relabeled as peer transport failure.
           (signals ethereum-lisp.validation:block-validation-error
             (ethereum-lisp.eth-sync:eth-sync-import-headers-with-bodies
              nil (list header)
              (lambda (block)
                (declare (ignore block))
                (error 'ethereum-lisp.validation:block-validation-error
                       :message "Injected importer validation failure"))))
           ;; Unknown implementation failures likewise retain their original
           ;; condition rather than entering peer failover policy.
           (signals type-error
             (ethereum-lisp.eth-sync:eth-sync-import-headers-with-bodies
              nil (list header)
              (lambda (block)
                (declare (ignore block))
                (error 'type-error :datum :broken :expected-type 'integer)))))
      (setf (fdefinition fetch-symbol) original-fetch))))

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

(defun eth-sync-serve-chain (peer chain-length &key body-limit)
  "Answer eth header and body requests for a canned chain of CHAIN-LENGTH blocks
(numbered 1..CHAIN-LENGTH, empty bodies) until the peer disconnects.
BODY-LIMIT simulates geth's soft response-byte limit by returning only a prefix."
  (let ((chain (eth-sync-test-chain-headers chain-length)))
    (handler-case
      (loop
        (multiple-value-bind (eth-id payload) (eth-peer-read peer)
          (cond
            ((= eth-id ethereum-lisp.eth-wire:+eth-message-get-block-headers+)
             (let* ((req (ethereum-lisp.eth-wire:decode-eth-get-block-headers payload))
                    (origin (ethereum-lisp.eth-wire:eth-get-block-headers-origin-number req))
                    (amount (ethereum-lisp.eth-wire:eth-get-block-headers-amount req))
                    (rid (ethereum-lisp.eth-wire:eth-get-block-headers-request-id req))
                    (headers
                      (loop for n from origin below (+ origin amount)
                            when (<= 1 n chain-length)
                              collect (nth (1- n) chain))))
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
                                    (if body-limit
                                        (subseq hashes 0
                                                (min body-limit
                                                     (length hashes)))
                                        hashes)))))))))
      (rlpx-disconnect () nil))))

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
                                  (eth-sync-serve-chain peer chain-length
                                                        :body-limit 2))
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
                            ;; Ask for the whole chain at once. The scripted
                            ;; peer serves at most two bodies per response, as
                            ;; geth does when its 2 MiB soft limit is reached.
                            (count (eth-sync-download-blocks
                                    peer
                                    (lambda (block)
                                      (push (block-header-number (block-header block))
                                            imported))
                                    :start-number 1 :batch-size 5)))
                       ;; Tell the server we are done so it stops serving.
                       (rlpx-send-disconnect connection +devp2p-message-disconnect+)
                       (is (= chain-length count))
                       ;; Blocks were imported in ascending order across batches.
                       (is (equal '(1 2 3 4 5) (nreverse imported)))))
                   (sb-thread:join-thread server-thread)
                   (when server-error
                     (error "eth sync server side failed: ~A" server-error))))))
        (ignore-errors (sb-bsd-sockets:socket-close listener))))))

(deftest eth-sync-multi-peer-resumes-soft-limited-body-and-receipt-prefixes
  (:layer :integration :module :p2p)
  ;; One requested range may produce several honest responses: GetBlockBodies
  ;; and GetReceipts both stop at a soft byte budget. Each short prefix replaces
  ;; its resident delivery with the exact suffix, so no height is skipped and
  ;; the bounded window does not grow.
  (let* ((chain (coerce (eth-sync-test-chain-headers 8) 'vector))
         (empty-body
           (ethereum-lisp.eth-wire:make-eth-block-body
            :transactions '() :ommers '()))
         (header-requests '())
         (imported '())
         (source
           (make-eth-sync-peer-source
            nil :id :soft-limited :head-number 8
            :fetch-headers
            (lambda (origin amount)
              (push (list origin amount) header-requests)
              (loop for number from origin below (+ origin amount)
                    collect (aref chain (1- number))))
            :fetch-bodies
            (lambda (headers)
              (loop repeat (min 3 (length headers)) collect empty-body))
            :fetch-receipts
            (lambda (headers)
              (values (loop repeat (min 2 (length headers)) collect '()) nil)))))
    (is (= 8
           (eth-sync-download-blocks-multi
            (list source)
            (lambda (block)
              (push (block-header-number (block-header block)) imported))
            :start-number 1 :target-number 8 :batch-size 8
            :request-timeout-seconds 1d0)))
    (is (equal '((1 8) (3 6) (5 4) (7 2))
               (nreverse header-requests)))
    (is (equal '(1 2 3 4 5 6 7 8) (nreverse imported)))))

(deftest eth-sync-multi-normalizes-typed-wire-receipts-before-root-validation
  (:layer :unit :module :p2p)
  (let* ((transaction
           (make-dynamic-fee-transaction
            :chain-id 1 :nonce 2 :max-fee-per-gas 10
            :max-priority-fee-per-gas 1 :gas-limit 21000
            :value 3 :data #(1) :y-parity 0 :r 4 :s 5))
         (receipt (make-receipt :status 1 :cumulative-gas-used 21000))
         (header
           (make-block-header
            :number 1 :difficulty 0 :gas-limit 30000000
            :receipts-root
            (ethereum-lisp.receipts:transaction-receipt-list-root
             (list transaction) (list receipt))))
         (body
           (ethereum-lisp.eth-wire:make-eth-block-body
            :transactions (list transaction) :ommers '()))
         (block
           (ethereum-lisp.blocks:make-block-from-parts
            :header header :transactions (list transaction)
            :receipts (list receipt))))
    (multiple-value-bind (request-id wire-groups incomplete-p)
        (ethereum-lisp.eth-wire:decode-eth-receipts
         (ethereum-lisp.eth-wire:encode-eth-receipts
          41 (list block) ethereum-lisp.eth-wire:+eth-protocol-version-69+)
         ethereum-lisp.eth-wire:+eth-protocol-version-69+)
      (is (= 41 request-id))
      (is (null incomplete-p))
      (let ((normalized
              (ethereum-lisp.eth-sync::eth-sync-validate-receipt-delivery
               (list header) (list body) wire-groups nil)))
        (is (= 1 (length normalized)))
        (is (typep (first (first normalized))
                   'ethereum-lisp.receipts:receipt))
        (is (= 1 (receipt-status (first (first normalized))))))
      ;; The redundant eth/69 type is part of validation, not metadata to drop.
      (setf
       (ethereum-lisp.eth-wire:eth-wire-receipt-transaction-type
        (first (first wire-groups)))
       3)
      (signals ethereum-lisp.eth-sync::eth-sync-malformed-delivery
        (ethereum-lisp.eth-sync::eth-sync-validate-receipt-delivery
         (list header) (list body) wire-groups nil)))))

(deftest eth-sync-three-scripted-peers-fail-over-without-blocking
  (:layer :integration :module :p2p)
  ;; Three batches are initially in flight. One peer never delivers until the
  ;; coordinator cancels it, one returns a malformed header range, and the good
  ;; peer must fill both holes. If timeout/failover or ordered assembly regresses,
  ;; this test takes the slow peer's five-second path or imports out of order.
  (let* ((chain (coerce (eth-sync-test-chain-headers 6) 'vector))
         (empty-body
           (ethereum-lisp.eth-wire:make-eth-block-body
            :transactions '() :ommers '()))
         (cancelled nil)
         (slow-started nil)
         (penalties '())
         (events '())
         (imported '())
         (maximum-in-flight 0)
         (started-at (get-internal-real-time)))
    (labels ((good-headers (origin amount)
               (loop for number from origin below (+ origin amount)
                     collect (aref chain (1- number))))
             (bodies (headers)
               (loop repeat (length headers) collect empty-body))
             (receipts (headers)
               (values (loop repeat (length headers) collect '()) nil))
             (note-penalty (peer)
               (lambda (reason score detail)
                 (declare (ignore detail))
                 (push (list peer reason score) penalties)))
             (source (id header-function &key cancel)
               (make-eth-sync-peer-source
                nil :id id :head-number 6
                :fetch-headers header-function
                :fetch-bodies #'bodies
                :fetch-receipts #'receipts
                :penalty (note-penalty id)
                :cancel cancel)))
      (let* ((slow
               (source
                :slow
                (lambda (origin amount)
                  (setf slow-started t)
                  (loop repeat 1000
                        until cancelled
                        do (sleep 0.005d0))
                  (when cancelled
                    (error "scripted slow peer cancelled"))
                  (good-headers origin amount))
                :cancel (lambda () (setf cancelled t))))
             (bad
               (source
                :bad
                (lambda (origin amount)
                  (declare (ignore origin))
                  (loop for number from 101
                        repeat amount
                        collect (eth-sync-test-header number)))))
             (good (source :good #'good-headers))
             (count
               (eth-sync-download-blocks-multi
                (list slow bad good)
                (lambda (block)
                  (push (block-header-number (block-header block)) imported))
                :start-number 1
                :target-number 6
                :batch-size 2
                :request-timeout-seconds 0.05d0
                :progress
                (lambda (snapshot event)
                  (is (= 6 (getf snapshot :pivot)))
                  (setf maximum-in-flight
                        (max maximum-in-flight
                             (getf snapshot :in-flight)
                             (or (getf event :in-flight) 0)))
                  (push event events)))))
        (let ((elapsed
                (/ (- (get-internal-real-time) started-at)
                   (float internal-time-units-per-second 1d0))))
          (is (= 6 count))
          (is (equal '(1 2 3 4 5 6) (nreverse imported)))
          (is slow-started)
          (is cancelled)
          (is (< elapsed 2d0))
          (is (>= maximum-in-flight 2))
          (is (find :timeout penalties :key #'second))
          (is (find :malformed penalties :key #'second))
          (is (find :headers events :key (lambda (event)
                                           (getf event :stage))))
          (is (find :bodies events :key (lambda (event)
                                          (getf event :stage))))
          (is (find :receipts events :key (lambda (event)
                                            (getf event :stage)))))))))

(deftest eth-sync-multi-peer-download-window-is-independent-of-target-height
  (:layer :integration :module :p2p)
  ;; Origin 1 deliberately stalls while the other worker races ahead.  With
  ;; two peers the resident window is four batches, so no request above block 4
  ;; may be constructed until the first batch is imported, even though the CL
  ;; target is much farther away.
  (let* ((chain (coerce (eth-sync-test-chain-headers 40) 'vector))
         (empty-body
           (ethereum-lisp.eth-wire:make-eth-block-body
            :transactions '() :ommers '()))
         (first-batch-released-p nil)
         (maximum-origin-before-release 0)
         (imported '()))
    (labels ((headers (origin amount)
               (if (= origin 1)
                   (progn
                     (sleep 0.1d0)
                     (setf first-batch-released-p t))
                   (unless first-batch-released-p
                     (setf maximum-origin-before-release
                           (max maximum-origin-before-release origin))))
               (loop for number from origin below (+ origin amount)
                     collect (aref chain (1- number))))
             (bodies (headers)
               (loop repeat (length headers) collect empty-body))
             (receipts (headers)
               (values (loop repeat (length headers) collect '()) nil))
             (source (id)
               (make-eth-sync-peer-source
                nil :id id :head-number 40
                :fetch-headers #'headers
                :fetch-bodies #'bodies
                :fetch-receipts #'receipts)))
      (is (= 40
             (eth-sync-download-blocks-multi
              (list (source :first) (source :second))
              (lambda (block)
                (push (block-header-number (block-header block)) imported))
              :start-number 1 :target-number 40 :batch-size 1
              :request-timeout-seconds 2d0)))
      (is (<= maximum-origin-before-release 4))
      (is (equal (loop for number from 1 to 40 collect number)
                 (nreverse imported))))))

(deftest eth-sync-rejects-a-divergent-consensus-target-before-import
  (:layer :integration :module :p2p)
  (let* ((chain (eth-sync-test-chain-headers 2))
         (empty-body
           (ethereum-lisp.eth-wire:make-eth-block-body
            :transactions '() :ommers '()))
         (imports 0)
         (source
           (make-eth-sync-peer-source
            nil :id :divergent :head-number 2
            :fetch-headers
            (lambda (origin amount)
              (subseq chain (1- origin) (+ (1- origin) amount)))
            :fetch-bodies
            (lambda (headers)
              (loop repeat (length headers) collect empty-body))
            :fetch-receipts
            (lambda (headers)
              (values (loop repeat (length headers) collect '()) nil)))))
    (signals ethereum-lisp.eth-sync:eth-sync-multi-peer-error
      (eth-sync-download-blocks-multi
       (list source)
       (lambda (block)
         (declare (ignore block))
         (incf imports))
       :start-number 1 :target-number 2 :batch-size 2
       :expected-target-hash (make-hash32 (make-array 32 :initial-element #xff))
       :request-timeout-seconds 1d0))
    (is (zerop imports))))

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

(deftest eth-sync-multiplexes-eth-72-and-snap-1-over-one-socket
  (:layer :integration :module :p2p :requires-local-sockets t)
  (let* ((config (eth-sync-test-config))
         (server-static
           #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
           #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (backend
           (ethereum-lisp.snap:make-snap-state-backend
            :account-range
            (lambda (request)
              (ethereum-lisp.snap:make-snap-account-range
               (ethereum-lisp.snap:snap-get-account-range-id request)
               '() '()))))
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
                            (declare (ignore host port))
                            (unless socket
                              (error "snap multiplex test did not accept a socket"))
                            (unwind-protect
                                 (let ((peer
                                         (eth-sync-accept-peer
                                          socket server-static (status)
                                          :client-id "ethereum-lisp/snap-server"
                                          :snap-backend backend)))
                                   (multiple-value-bind (kind id payload)
                                       (eth-peer-read-once peer)
                                     (unless (and (eq kind :snap)
                                                  (= id
                                                     ethereum-lisp.snap:+snap-message-get-account-range+))
                                       (error "expected a snap account-range request"))
                                     (ethereum-lisp.eth-sync:eth-peer-serve-snap-message
                                      peer id payload))
                                   (setf server-result
                                         (list :eth-version
                                               (eth-peer-eth-version peer)
                                               :snap-offset
                                               (ethereum-lisp.eth-sync:eth-peer-snap-offset
                                                peer))))
                              (ignore-errors
                               (sb-bsd-sockets:socket-close socket))))
                        (error (condition) (setf server-error condition))))
                    :name "eth-snap-multiplex-test-server")))
             (multiple-value-bind (peer socket)
                 (eth-sync-connect-peer
                  "127.0.0.1" (eth-sync-listener-port listener)
                  server-static-pub client-static (status)
                  :client-id "ethereum-lisp/snap-client"
                  :snap-backend backend)
               (unwind-protect
                    (let* ((request
                             (ethereum-lisp.snap:make-snap-get-account-range
                              42 *eth-sync-test-best*
                              (make-byte-vector 32)
                              (make-byte-vector 32 :initial-element #xff)
                              1024))
                           (response
                             (ethereum-lisp.eth-sync:eth-peer-snap-request
                              peer
                              ethereum-lisp.snap:+snap-message-get-account-range+
                              request)))
                      (is (= 72 (eth-peer-eth-version peer)))
                      (is (integerp
                           (ethereum-lisp.eth-sync:eth-peer-snap-offset peer)))
                      (is (= 42
                             (ethereum-lisp.snap:snap-account-range-id
                              response)))
                      (is (null
                           (ethereum-lisp.snap:snap-account-range-accounts
                            response))))
                 (ignore-errors (sb-bsd-sockets:socket-close socket))))
             (is (not (eq :timeout
                          (sb-thread:join-thread server-thread
                                                 :timeout 15
                                                 :default :timeout))))
             (when server-error
               (error "snap multiplex server failed: ~A" server-error))
             (is (= 72 (getf server-result :eth-version)))
             (is (integerp (getf server-result :snap-offset))))
        (eth-sync-listener-close listener)))))

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

(deftest eth-wire-read-once-surfaces-keepalives-instead-of-swallowing-them
  (:layer :integration :module :p2p :requires-local-sockets t)
  ;; ETH-WIRE-READ loops until a subprotocol message arrives, answering Ping and
  ;; discarding Pong below the caller. A session that is only being kept alive
  ;; therefore never returns from it — which is fine for a caller awaiting a
  ;; reply and fatal for a loop that must also notice a shutdown. READ-ONCE is
  ;; the version that hands base traffic back, and this is its proof.
  (let* ((config (eth-sync-test-config))
         (server-static
          #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291)
         (client-static
          #x49a7b37aa6f6645917e7b807e9d1c00d4fa71f18343b0d4122a4d2df64dd6fee)
         (server-static-pub (secp256k1-private-key-public-key server-static))
         (transaction (make-legacy-transaction :nonce 1 :gas-price 2
                                               :gas-limit 21000 :value 3
                                               :data #(1) :v 27 :r 4 :s 5))
         (listener (make-instance 'sb-bsd-sockets:inet-socket
                                  :type :stream :protocol :tcp)))
    (flet ((hello (client-id)
             (make-devp2p-hello
              :client-id client-id
              :capabilities (list (make-devp2p-capability "eth" 68))
              :listen-port 30399
              :node-id server-static-pub))
           (status ()
             (eth-build-status config *eth-sync-test-genesis* 0 0
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
               (let ((server-error nil)
                     (server-thread nil))
                 (setf server-thread
                       (sb-thread:make-thread
                        (lambda ()
                          (handler-case
                              (let* ((accepted (sb-bsd-sockets:socket-accept listener))
                                     (stream (p2p-binary-socket-stream accepted))
                                     (connection (rlpx-accept-stream stream
                                                                     server-static))
                                     (peer (eth-peer-connect connection
                                                             (hello "srv") (status))))
                                ;; A keepalive, then real work.
                                (rlpx-send-ping (eth-peer-connection peer))
                                (eth-peer-send
                                 peer
                                 ethereum-lisp.eth-wire:+eth-message-transactions+
                                 (ethereum-lisp.eth-wire:encode-eth-transactions
                                  (list transaction))))
                            (error (condition) (setf server-error condition))))
                        :name "eth-read-once-test-server"))
                 (let ((client-socket (make-instance 'sb-bsd-sockets:inet-socket
                                                     :type :stream :protocol :tcp)))
                   (unwind-protect
                        (progn
                          (sb-bsd-sockets:socket-connect
                           client-socket
                           (sb-bsd-sockets:make-inet-address "127.0.0.1") port)
                          (let* ((stream (p2p-binary-socket-stream client-socket))
                                 (connection (rlpx-connect-stream stream client-static
                                                                  server-static-pub))
                                 (peer (eth-peer-connect connection (hello "cli")
                                                         (status))))
                            ;; The Hello is kept now, not discarded.
                            (is (string= "srv" (eth-peer-remote-client-id peer)))
                            (is (= 30399 (eth-peer-remote-listen-port peer)))
                            ;; The keepalive reaches us instead of being absorbed.
                            (multiple-value-bind (kind id payload)
                                (eth-peer-read-once peer)
                              (declare (ignore payload))
                              (is (eq :base kind))
                              (is (= +devp2p-message-ping+ id)))
                            ;; And the next read is the subprotocol message.
                            (multiple-value-bind (kind id payload)
                                (eth-peer-read-once peer)
                              (is (eq :eth kind))
                              (is (= ethereum-lisp.eth-wire:+eth-message-transactions+
                                     id))
                              (is (= 1 (length
                                        (ethereum-lisp.eth-wire:decode-eth-transactions
                                         payload)))))))
                     (ignore-errors (sb-bsd-sockets:socket-close client-socket))))
                 (is (not (eq :timeout
                              (sb-thread:join-thread server-thread
                                                     :timeout 10
                                                     :default :timeout))))
                 (when server-error
                   (error "read-once server side failed: ~A" server-error)))))
        (ignore-errors (sb-bsd-sockets:socket-close listener))))))
