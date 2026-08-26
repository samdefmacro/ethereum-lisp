(in-package #:ethereum-lisp.test)

;;;; The admin namespace: what it reports, and — more important — who is
;;;; allowed to reach it.

(defun admin-test-backend
    (&key (listening t) (peers '()) (added '()) (removed '()))
  "A backend answering from fixed data, so these tests state the RPC surface
rather than a node's peering state."
  (declare (ignore added removed))
  (make-admin-backend
   :listening-p (lambda () listening)
   :peer-count (lambda () (length peers))
   :peers (lambda () peers)
   :node-info (lambda ()
                (list :enode-id (make-string 64 :initial-element #\a)
                      :client-id "ethereum-lisp"
                      :enode "enode://ab@127.0.0.1:30303"
                      :ip "127.0.0.1"
                      :listener-port 30303
                      :listen-address "127.0.0.1:30303"
                      :eth (list :network-id 1337 :genesis "0xaa" :head "0xbb")))
   :add-peer (lambda (enode) (declare (ignore enode)) t)
   :remove-peer (lambda (enode) (declare (ignore enode)) t)))

(defun admin-test-json-rpc (method backend)
  "Exercise METHOD through the shipped request dispatch and JSON writer."
  (engine-rpc-handle-request-json
   (format nil
           "{\"jsonrpc\":\"2.0\",\"id\":41,\"method\":\"~A\",\"params\":[]}"
           method)
   (make-engine-payload-memory-store)
   (make-chain-config)
   :admin-backend backend))

(deftest admin-namespace-is-reachable-only-when-named
  ;; THE security property. With no --http.api the filter falls back to the
  ;; default public predicate, so admin_ must not be part of it — otherwise
  ;; admin_addPeer is answered on a default-open HTTP port.
  (is (not (engine-rpc-public-method-p "admin_nodeInfo")))
  (is (not (engine-rpc-public-method-p "admin_addPeer")))
  (is (engine-rpc-admin-method-p "admin_nodeInfo"))
  (is (not (engine-rpc-admin-method-p "eth_chainId")))
  ;; Default filter: admin is unreachable.
  (let ((default (ethereum-lisp.cli::devnet-cli-public-api-method-filter nil)))
    (is (funcall default "eth_chainId"))
    (is (not (funcall default "admin_nodeInfo")))
    (is (not (funcall default "admin_addPeer"))))
  ;; Naming other modules does not smuggle admin in.
  (let ((eth-only (ethereum-lisp.cli::devnet-cli-public-api-method-filter
                   (list "eth" "debug"))))
    (is (funcall eth-only "eth_chainId"))
    (is (not (funcall eth-only "admin_nodeInfo"))))
  ;; Naming it explicitly is the only way in.
  (let ((with-admin (ethereum-lisp.cli::devnet-cli-public-api-method-filter
                     (list "eth" "admin"))))
    (is (funcall with-admin "admin_nodeInfo"))
    (is (funcall with-admin "admin_peers"))
    (is (funcall with-admin "admin_addPeer"))
    (is (funcall with-admin "admin_removePeer")))
  ;; And rpc_modules advertises it on exactly the same rule.
  (is (null (assoc "admin"
                   (ethereum-lisp.public-api::engine-rpc-handle-rpc-modules
                    nil (ethereum-lisp.cli::devnet-cli-public-api-method-filter
                         (list "eth")))
                   :test #'string=)))
  (is (assoc "admin"
             (ethereum-lisp.public-api::engine-rpc-handle-rpc-modules
              nil (ethereum-lisp.cli::devnet-cli-public-api-method-filter
                   (list "admin")))
             :test #'string=)))

(deftest node-id-to-enode-id-hex-is-keccak-of-the-public-key
  ;; admin_nodeInfo.id and PeerInfo.ID are the 32-byte enode id, NOT the 64-byte
  ;; public key that goes inside an enode URL. Confusing them is invisible until
  ;; another client rejects the value.
  (let* ((node-id (node-id-from-private-key
                   #xb71c71a67e1177ad4e901695e1b4b9ee17ae16c6668d313eac2f96dbcda3f291))
         (short (node-id-to-enode-id-hex node-id))
         (long (node-id-to-hex node-id)))
    (is (= 64 (length short)))
    (is (= 128 (length long)))
    (is (not (string= short long)))
    ;; It really is keccak-256 of the key, not a truncation of it.
    (is (string= short (subseq (bytes-to-hex (hash32-bytes (keccak-256-hash node-id))) 2)))
    (is (not (string= short (subseq long 0 64))))))

(deftest admin-methods-report-the-backend-and-refuse-without-one
  (let ((backend (admin-test-backend
                  :peers (list (list :enode-id (make-string 64
                                                            :initial-element #\b)
                                     :client-id "geth/v1.17.4"
                                     :enode "enode://bb@10.0.0.2:30303"
                                     :remote-address "10.0.0.2:30303"
                                     :direction :inbound
                                     :eth-version 69)))))
    (let ((info (ethereum-lisp.public-api::engine-rpc-handle-admin-node-info
                 nil backend)))
      (is (= 64 (length (cdr (assoc "id" info :test #'string=)))))
      (is (string= "ethereum-lisp" (cdr (assoc "name" info :test #'string=))))
      (is (string= "127.0.0.1:30303"
                   (cdr (assoc "listenAddr" info :test #'string=)))))
    (let ((peers (ethereum-lisp.public-api::engine-rpc-handle-admin-peers
                  nil backend)))
      (is (= 1 (length peers)))
      (let ((peer (elt peers 0)))
        (is (string= "geth/v1.17.4" (cdr (assoc "name" peer :test #'string=))))
        ;; The eth version is this session's, never a global constant.
        (is (equal '(("version" . 69))
                   (cdr (assoc "eth" (cdr (assoc "protocols" peer
                                                 :test #'string=))
                               :test #'string=))))))
    ;; A malformed enode is a parameter error, not a failure inside a worker.
    (signals error
      (ethereum-lisp.public-api::engine-rpc-handle-admin-add-peer
       (list "not-an-enode") backend))
    (signals error
      (ethereum-lisp.public-api::engine-rpc-handle-admin-add-peer nil backend))
    (is (eq t
            (ethereum-lisp.public-api::engine-rpc-handle-admin-remove-peer
             (list
              "enode://ca634cae0d49acb401d8a15135d7683a4ca6390aa5375e1057c2691298d0b7d18261503a6c96a8aaf46e2f377217f75f640fd2d5f79d554768081b057760b6e6@127.0.0.1:30303")
             backend)))
    (signals error
      (ethereum-lisp.public-api::engine-rpc-handle-admin-remove-peer
       (list "not-an-enode") backend)))
  ;; A node built without peering says so rather than inventing an answer.
  (signals error
    (ethereum-lisp.public-api::engine-rpc-handle-admin-node-info nil nil))
  (signals error
    (ethereum-lisp.public-api::engine-rpc-handle-admin-peers nil nil)))

(deftest admin-responses-survive-production-json-encoding
  ;; Handler-level alists are not enough: NIL, JSON null, objects, and arrays
  ;; overlap in Lisp.  This is the same dispatch and writer used by HTTP.
  (let* ((peer (list :enode-id (make-string 64 :initial-element #\b)
                     :client-id "geth/v1.17.4"
                     :enode nil
                     :remote-address "10.0.0.2:30303"
                     :direction :inbound
                     :eth-version 69))
         (backend (admin-test-backend :peers (list peer)))
         (node-response
           (parse-json (admin-test-json-rpc "admin_nodeInfo" backend)
                       :preserve-types t))
         (peer-response
           (parse-json (admin-test-json-rpc "admin_peers" backend)
                       :preserve-types t))
         (node-result (cdr (assoc "result" node-response :test #'string=)))
         (peer-results (cdr (assoc "result" peer-response :test #'string=)))
         (first-peer (first peer-results))
         (network (cdr (assoc "network" first-peer :test #'string=))))
    (is (ethereum-lisp.json:json-object-p
         (cdr (assoc "ports" node-result :test #'string=))))
    (is (= 30303
           (cdr (assoc "listener"
                       (cdr (assoc "ports" node-result :test #'string=))
                       :test #'string=))))
    (is (= 1 (length peer-results)))
    (is (ethereum-lisp.json:json-object-p network))
    (is (ethereum-lisp.json:json-null-p
         (cdr (assoc "localAddress" network :test #'string=))))
    (is (ethereum-lisp.json:json-null-p
         (cdr (assoc "enode" first-peer :test #'string=)))))
  ;; Empty peer sets are arrays, never JSON null.
  (is (search "\"result\":[]"
              (admin-test-json-rpc "admin_peers" (admin-test-backend)))))

(deftest admin-node-info-falls-back-to-genesis-before-a-canonical-head
  ;; A restored/snap-sync store can temporarily report head number zero before
  ;; its canonical-number index is populated.  Operator RPC must still identify
  ;; the node instead of turning that transient state into -32603.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0))
         (empty-store (make-engine-payload-memory-store))
         (backend (ethereum-lisp.cli::devnet-node-admin-backend (list node)))
         (genesis-hash
           (hash32-to-hex
            (block-hash (ethereum-lisp.cli:devnet-node-genesis-block node)))))
    (setf (ethereum-lisp.cli:devnet-node-store node) empty-store)
    (let* ((response
             (parse-json (admin-test-json-rpc "admin_nodeInfo" backend)))
           (result (cdr (assoc "result" response :test #'string=)))
           (eth (and result
                     (cdr (assoc "eth"
                                 (cdr (assoc "protocols" result :test #'string=))
                                 :test #'string=)))))
      (is result)
      (is (string= genesis-hash
                   (cdr (assoc "head" eth :test #'string=)))))))

(deftest admin-node-info-does-not-recursively-acquire-the-request-store-guard
  ;; Both shipped HTTP services run the complete RPC request under NODE's
  ;; store guard.  The admin backend must read the store directly inside that
  ;; protected request; acquiring the same SBCL mutex again turns a healthy
  ;; admin_nodeInfo call into -32603 in the real server.
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0))
         (backend (ethereum-lisp.cli::devnet-node-admin-backend (list node)))
         (response
           (parse-json
            (engine-rpc-handle-request-json
             "{\"jsonrpc\":\"2.0\",\"id\":42,\"method\":\"admin_nodeInfo\",\"params\":[]}"
             (ethereum-lisp.cli:devnet-node-store node)
             (make-chain-config)
             :admin-backend backend
             :request-guard-function
             (ethereum-lisp.cli::devnet-node-store-guard-function node)))))
    (is (assoc "result" response :test #'string=))
    (is (null (assoc "error" response :test #'string=)))))

(deftest eth-syncing-snapshot-does-not-wait-for-the-store-guard
  #-sbcl
  (skip-test "Store-guard contention probe requires SBCL threads")
  #+sbcl
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0))
         (backend (ethereum-lisp.cli::devnet-node-admin-backend (list node)))
         (snapshot-function
           (ethereum-lisp.public-api::admin-backend-syncing backend))
         (entered (sb-thread:make-semaphore :count 0))
         (release (sb-thread:make-semaphore :count 0))
         (holder
           (sb-thread:make-thread
            (lambda ()
              (ethereum-lisp.cli::call-with-devnet-node-store-guard
               node
               (lambda ()
                 (sb-thread:signal-semaphore entered)
                 (sb-thread:wait-on-semaphore release))))))
         (engine-context
           (ethereum-lisp.rpc-http:engine-rpc-http-service-rpc-context
            (ethereum-lisp.cli:devnet-node-service node)))
         (guard-predicate
           (ethereum-lisp.rpc::rpc-context-request-guard-predicate
            engine-context)))
    (unwind-protect
         (progn
           (sb-thread:wait-on-semaphore entered)
           (let ((contended (funcall snapshot-function)))
             (is (listp contended))
             (is (string= "0x0"
                          (cdr (assoc "highestBlock" contended
                                      :test #'string=))))))
      (sb-thread:signal-semaphore release)
      (sb-thread:join-thread holder))
    (is (eq :false (funcall snapshot-function)))
    (is (not (funcall guard-predicate "eth_syncing")))
    (is (funcall guard-predicate "engine_newPayloadV4"))))

(deftest net-listening-and-peer-count-follow-the-peering-backend
  ;; Both were hardcoded to false and 0x0. A node answering admin_peers with
  ;; three peers and net_peerCount with zero is worse than one answering neither.
  (is (eq :false (ethereum-lisp.public-api::engine-rpc-handle-net-listening nil)))
  (is (string= "0x0" (ethereum-lisp.public-api::engine-rpc-handle-net-peer-count
                      nil)))
  (let ((backend (admin-test-backend :listening t :peers (list :a :b :c))))
    (is (eq t (ethereum-lisp.public-api::engine-rpc-handle-net-listening
               nil backend)))
    (is (string= "0x3"
                 (ethereum-lisp.public-api::engine-rpc-handle-net-peer-count
                  nil backend))))
  (let ((quiet (admin-test-backend :listening nil)))
    (is (eq :false (ethereum-lisp.public-api::engine-rpc-handle-net-listening
                    nil quiet)))))
