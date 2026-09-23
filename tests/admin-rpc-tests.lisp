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
         (start (sb-thread:make-semaphore :count 0))
         (entered (sb-thread:make-semaphore :count 0))
         (release (sb-thread:make-semaphore :count 0))
         (holder
           (sb-thread:make-thread
            (lambda ()
              (sb-thread:wait-on-semaphore start)
              (ethereum-lisp.cli::call-with-devnet-node-store-guard
               node
               (lambda ()
                 (engine-payload-store-put-forkchoice-sync-target
                  (ethereum-lisp.cli:devnet-node-store node)
                  (make-hash32
                   (make-byte-vector 32 :initial-element #x44)))
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
           ;; Establish the exact stale cache state from the regression: the
           ;; node was idle at the last successful guarded refresh.
           (is (eq :false (funcall snapshot-function)))
           (sb-thread:signal-semaphore start)
           (sb-thread:wait-on-semaphore entered)
           (let ((contended (funcall snapshot-function)))
             (is (listp contended))
             (is (string= "0x0"
                          (cdr (assoc "highestBlock" contended
                                      :test #'string=))))))
      (sb-thread:signal-semaphore release)
      (sb-thread:join-thread holder))
    (is (listp (funcall snapshot-function)))
    (is (not (funcall guard-predicate "eth_syncing")))
    (is (funcall guard-predicate "engine_newPayloadV4"))))

(deftest eth-syncing-node-snapshot-reports-known-target-before-publication
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (backend (ethereum-lisp.cli::devnet-node-admin-backend (list node)))
         (snapshot-function
           (ethereum-lisp.public-api::admin-backend-syncing backend))
         (block
           (make-block
            :header
            (make-block-header
             :parent-hash (zero-hash32)
             :number 7
             :timestamp 1
             :gas-limit 30000000)))
         (target-hash (block-hash block)))
    (engine-payload-store-put-block
     store block :state-available-p nil :canonicalize-p nil)
    (engine-payload-store-put-forkchoice-sync-target
     store target-hash :block-number 7)
    (let ((snapshot (funcall snapshot-function)))
      (is (listp snapshot))
      (is (string= "0x0"
                   (cdr (assoc "currentBlock" snapshot :test #'string=))))
      (is (string= "0x7"
                   (cdr (assoc "highestBlock" snapshot :test #'string=)))))
    ;; Executability does not end sync before the pending CL forkchoice is
    ;; canonically published.
    (engine-payload-store-put-block
     store block :state-available-p t :canonicalize-p nil)
    (let ((snapshot (funcall snapshot-function)))
      (is (listp snapshot))
      (is (string= "0x7"
                   (cdr (assoc "highestBlock" snapshot :test #'string=)))))))

(deftest eth-syncing-reports-the-durable-snap-skeleton-target
  (:layer :integration :module :cli)
  (let ((path
          (merge-pathnames
           (make-pathname
            :directory
            `(:relative
              ,(format nil "ethereum-lisp-snap-syncing-~A" (gensym))))
           #P"/private/tmp/")))
    (unwind-protect
         (ethereum-lisp.cli::call-with-devnet-cli-kv-database-cache
          (lambda ()
            (let* ((node
                     (ethereum-lisp.cli:make-devnet-node
                      :genesis-json *eth-sync-paris-genesis-json*
                      :database-path path :db-engine :rocksdb
                      :port 0 :public-port 0))
                   (store (ethereum-lisp.cli::devnet-node-store node))
                   (database
                     (ethereum-lisp.node-store.persistence:database-engine-payload-store-database
                      store))
                   (genesis-hash
                     (block-hash
                      (ethereum-lisp.cli::devnet-node-genesis-block node)))
                   (authority-id
                     (ethereum-lisp.cli::devnet-persistence-state-authority-id
                      (ethereum-lisp.cli::devnet-node-persistence-state node)))
                   (target-hash
                     (make-hash32
                      (make-byte-vector 32 :initial-element #x42)))
                   (progress
                     (ethereum-lisp.node-store.persistence:make-node-store-snap-skeleton-progress
                      :authority-id authority-id
                      :chain-id
                      (chain-config-chain-id
                       (ethereum-lisp.cli::devnet-node-config node))
                      :genesis-hash genesis-hash
                      :target-number 100 :target-hash target-hash
                      :anchor-number 36 :anchor-hash genesis-hash
                      :pivot-number 36 :pivot-hash genesis-hash
                      :last-number 36 :last-hash genesis-hash))
                   (backend
                     (ethereum-lisp.cli::devnet-node-admin-backend (list node)))
                   (snapshot-function
                     (ethereum-lisp.public-api::admin-backend-syncing backend)))
              (let ((batch (make-kv-write-batch)))
                (ethereum-lisp.node-store.persistence::node-store-populate-snap-skeleton-progress-batch
                 database batch progress)
                (kv-apply-batch database batch))
              ;; The target has already left the in-memory remote-block list,
              ;; as it does before AccountRange and healer work begin.  The
              ;; durable CL-authorized skeleton must keep ETH_SYNCING truthful
              ;; even while that long import owns the ordinary store guard.
              (is (null (engine-payload-store-remote-block-list store)))
              #+sbcl
              (let* ((entered (sb-thread:make-semaphore :count 0))
                     (release (sb-thread:make-semaphore :count 0))
                     (holder
                       (sb-thread:make-thread
                        (lambda ()
                          (ethereum-lisp.cli::call-with-devnet-node-store-guard
                           node
                           (lambda ()
                             (sb-thread:signal-semaphore entered)
                             (sb-thread:wait-on-semaphore release)))))))
                (unwind-protect
                     (progn
                       (sb-thread:wait-on-semaphore entered)
                       (is (= 100
                              (ethereum-lisp.cli::devnet-node-durable-snap-highest-block
                               node)))
                       (let ((snapshot (funcall snapshot-function)))
                         (is (listp snapshot))
                         (is (string= "0x0"
                                      (cdr (assoc "currentBlock" snapshot
                                                  :test #'string=))))
                         (is (string= "0x64"
                                      (cdr (assoc "highestBlock" snapshot
                                                  :test #'string=))))))
                  (sb-thread:signal-semaphore release)
                  (sb-thread:join-thread holder)))
              #-sbcl
              (let ((snapshot (funcall snapshot-function)))
                (is (listp snapshot))
                (is (string= "0x64"
                             (cdr (assoc "highestBlock" snapshot
                                         :test #'string=)))))
              (ethereum-lisp.node-store.persistence:node-store-delete-snap-skeleton-progress
               database)
              (is (eq :false (funcall snapshot-function))))))
      (uiop:delete-directory-tree path
                                  :validate t
                                  :if-does-not-exist :ignore))))

(defun admin-test-extend-canonical-chain (store parent count)
  "Canonically append COUNT empty blocks after PARENT; return the new tip."
  (loop repeat count
        do (let ((block
                   (make-block
                    :header
                    (make-block-header
                     :parent-hash (block-hash parent)
                     :number (1+ (block-header-number (block-header parent)))
                     :timestamp (1+ (block-header-timestamp
                                     (block-header parent)))
                     :gas-limit 30000000))))
             (engine-payload-store-put-block
              store block :state-available-p t :canonicalize-p t)
             (setf parent block)))
  parent)

(defun admin-test-syncing-under-sustained-guard-contention
    (advance-to &key probe)
  "Return (VALUES BEFORE DURING) eth_syncing answers around a busy store guard.

A remote block at height 5 is the only sync target. BEFORE is answered with the
guard free. Another thread then takes the guard, advances the canonical head to
ADVANCE-TO, releases, and immediately takes the guard again and keeps it: the
live Hoodi pattern, where block execution, batch import and Engine handlers
hold the guard back to back and eth_syncing's try-lock never finds it free.
DURING is answered while that second hold is in progress.

PROBE, when given, is a function of the node returning the no-argument
function to answer BEFORE and DURING with, in place of eth_syncing."
  #-sbcl
  (progn advance-to probe (skip-test "Store-guard contention probe requires SBCL threads"))
  #+sbcl
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0))
         (store (ethereum-lisp.cli:devnet-node-store node))
         (genesis (ethereum-lisp.cli:devnet-node-genesis-block node))
         (backend (ethereum-lisp.cli::devnet-node-admin-backend (list node)))
         (syncing (if probe
                      (funcall probe node)
                      (ethereum-lisp.public-api::admin-backend-syncing backend)))
         (entered (sb-thread:make-semaphore :count 0))
         (release (sb-thread:make-semaphore :count 0))
         (before nil)
         (during nil)
         (holder nil))
    (ethereum-lisp.chain-store:engine-payload-store-put-remote-block
     store
     (make-block
      :header (make-block-header :parent-hash (zero-hash32) :number 5
                                 :timestamp 5 :gas-limit 30000000)))
    (setf before (funcall syncing))
    (setf holder
          (sb-thread:make-thread
           (lambda ()
             (handler-case
                 (progn
                   (ethereum-lisp.cli::call-with-devnet-node-store-guard
                    node
                    (lambda ()
                      (admin-test-extend-canonical-chain
                       store genesis advance-to)))
                   (ethereum-lisp.cli::call-with-devnet-node-store-guard
                    node
                    (lambda ()
                      (sb-thread:signal-semaphore entered)
                      (sb-thread:wait-on-semaphore release))))
               (serious-condition (condition)
                 (sb-thread:signal-semaphore entered)
                 condition)))))
    (unwind-protect
         (progn
           (sb-thread:wait-on-semaphore entered)
           (is (= advance-to (chain-store-head-number store)))
           (setf during (funcall syncing)))
      (sb-thread:signal-semaphore release)
      (sb-thread:join-thread holder))
    (values before during)))

(deftest eth-syncing-turns-false-when-the-head-passes-the-target-under-guard-contention
  ;; Hoodi 2026-09-23 (revision 8e95b990): after the node caught up, the head
  ;; followed the chain but eth_syncing kept answering the pivot-era snapshot
  ;; for 20+ minutes, because every try-lock refresh found the store guard
  ;; busy and fell back to the last cached answer.
  (multiple-value-bind (before during)
      (admin-test-syncing-under-sustained-guard-contention 6)
    (is (listp before))
    (is (string= "0x0" (cdr (assoc "currentBlock" before :test #'string=))))
    (is (string= "0x5" (cdr (assoc "highestBlock" before :test #'string=))))
    (is (eq :false during))))

(deftest eth-syncing-under-guard-contention-reports-the-published-head-below-target
  ;; Positive control for the test above: a head still below the target keeps
  ;; reporting syncing, and currentBlock follows the head rather than the
  ;; snapshot taken before the contention began.
  (multiple-value-bind (before during)
      (admin-test-syncing-under-sustained-guard-contention 3)
    (is (listp before))
    (is (listp during))
    (is (string= "0x3" (cdr (assoc "currentBlock" during :test #'string=))))
    (is (string= "0x5" (cdr (assoc "highestBlock" during :test #'string=))))))

(defun admin-test-gossip-gate (node)
  "NODE's inbound transaction gossip gate, reached through the shipped serve
backend the peer sessions consult (pinned geth's Backend.AcceptTxs)."
  (let ((backend (ethereum-lisp.cli::devnet-peer-serve-backend node)))
    (lambda ()
      (ethereum-lisp.eth-sync::eth-accept-inbound-transactions-p backend))))

(deftest devnet-gossip-gate-admits-transactions-on-a-fresh-node-under-guard-contention
  (:layer :integration :module :p2p)
  ;; Hive engine-cancun "Blob Transaction Ordering, Multiple Clients" at
  ;; d203fee6 (2026-09-23): the payload producer's first-ever inbound
  ;; transaction announcement arrived while its store guard was busy (its RPC
  ;; handlers waited 0.7-1.6 s on the guard at the time), the gate fell back to
  ;; a verdict never computed (NIL), and the second client's single-blob
  ;; transactions were dropped before decoding and never re-announced, so the
  ;; first payload carried 5 blobs instead of 6. A node at its head with no
  ;; sync target must admit gossip whether or not the guard is free.
  #-sbcl
  (skip-test "Store-guard contention probe requires SBCL threads")
  #+sbcl
  (let* ((node (ethereum-lisp.cli:make-devnet-node
                :genesis-json *eth-sync-paris-genesis-json*
                :port 0))
         (gate (admin-test-gossip-gate node))
         (entered (sb-thread:make-semaphore :count 0))
         (release (sb-thread:make-semaphore :count 0))
         (holder
           (sb-thread:make-thread
            (lambda ()
              ;; An unhandled condition here would kill the whole suite run
              ;; rather than fail this test.
              (handler-case
                  (ethereum-lisp.cli::call-with-devnet-node-store-guard
                   node
                   (lambda ()
                     (sb-thread:signal-semaphore entered)
                     (sb-thread:wait-on-semaphore release)))
                (serious-condition (condition)
                  (sb-thread:signal-semaphore entered)
                  condition))))))
    (unwind-protect
         (progn
           (sb-thread:wait-on-semaphore entered)
           (is (eq t (and (funcall gate) t))))
      (sb-thread:signal-semaphore release)
      (sb-thread:join-thread holder))))

(deftest devnet-gossip-gate-follows-the-head-past-the-target-under-guard-contention
  (:layer :integration :module :p2p)
  ;; The stale-verdict half of the same defect: a refusal computed while a
  ;; target was ahead must not outlive the head reaching it just because every
  ;; later try-lock found the guard busy.
  (multiple-value-bind (before during)
      (admin-test-syncing-under-sustained-guard-contention
       6 :probe #'admin-test-gossip-gate)
    (is (null before))
    (is (eq t (and during t)))))

(deftest devnet-gossip-gate-still-refuses-below-the-target-under-guard-contention
  (:layer :integration :module :p2p)
  ;; Positive control for the two tests above: the gate is not simply open.
  ;; A head still below the sync target keeps refusing gossip under contention.
  (multiple-value-bind (before during)
      (admin-test-syncing-under-sustained-guard-contention
       3 :probe #'admin-test-gossip-gate)
    (is (null before))
    (is (null during))))

(deftest devnet-store-guard-release-hook-runs-on-every-release-and-never-fails-the-hold
  ;; The eth_syncing view is published from this hook, so every way of taking
  ;; the guard must run it -- including a hold that unwinds -- and a hook that
  ;; fails must leave the guarded operation's own result intact.
  (let* ((calls 0)
         (fail-p nil))
    (destructuring-bind (guard try priority pending ledger)
        (multiple-value-list
         (ethereum-lisp.cli::make-devnet-store-guard-function
          :release-hook (lambda ()
                          (incf calls)
                          (when fail-p (error "hook failure")))))
      (declare (ignore pending ledger))
      (is (eq :held (funcall guard (lambda () :held))))
      (is (= 1 calls))
      (is (equal '(:tried t)
                 (multiple-value-list (funcall try (lambda () :tried)))))
      (is (= 2 calls))
      (is (eq :engine (funcall priority (lambda () :engine))))
      (is (= 3 calls))
      (is (eq :unwound
              (block unwind
                (funcall guard (lambda () (return-from unwind :unwound))))))
      (is (= 4 calls))
      (setf fail-p t)
      (is (eq :still-held (funcall guard (lambda () :still-held))))
      (is (= 5 calls))))
  ;; Without a hook (the dial guard) results still pass straight through.
  (let ((guard (ethereum-lisp.cli::make-devnet-store-guard-function)))
    (is (eq :plain (funcall guard (lambda () :plain))))))

(deftest devnet-store-guard-names-the-holds-an-engine-request-waited-behind
  ;; On Hoodi (aee866f7) Engine requests with no execution took 5-25 s, and
  ;; their log could not say who held the store guard. A priority waiter now
  ;; reports guardWaitMs and guardWaitedFor (label:holdMs+hookMs of every hold
  ;; that ended while it waited), and a hold over the long-hold bound is
  ;; handed to LONG-HOLD-FUNCTION. Control: a waiter that found the guard free
  ;; reports nothing, and a short hold is not reported as long.
  #+sbcl
  (let ((long-holds '())
        (ethereum-lisp.cli::*devnet-store-guard-long-hold-ms* 200))
    (destructuring-bind (guard try priority pending ledger)
        (multiple-value-list
         (ethereum-lisp.cli::make-devnet-store-guard-function
          :release-hook (lambda () (sleep 0.02))
          :long-hold-function
          (lambda (hold)
            (push (ethereum-lisp.cli::devnet-store-guard-hold-label hold)
                  long-holds))))
      (declare (ignore try pending ledger))
      ;; Control: a free guard, and a short hold.
      (ethereum-lisp.telemetry:telemetry-call-with-wait-accounting
       (lambda ()
         (funcall priority (lambda () :free))
         (is (null (ethereum-lisp.telemetry:telemetry-wait-fields)))))
      (let ((ethereum-lisp.telemetry:*telemetry-activity-label* "short"))
        (funcall guard (lambda () :short)))
      (is (null long-holds))
      (sleep 0.01)
      (let* ((holding (sb-thread:make-semaphore))
             (holder
               (sb-thread:make-thread
                (lambda ()
                  ;; A condition here must not kill the suite process.
                  (handler-case
                      ;; A special binding is per thread: rebind the bound here.
                      (let ((ethereum-lisp.telemetry:*telemetry-activity-label*
                              "sync-gap-fill")
                            (ethereum-lisp.cli::*devnet-store-guard-long-hold-ms*
                              200))
                        (funcall guard
                                 (lambda ()
                                   (sb-thread:signal-semaphore holding)
                                   (sleep 0.4))))
                    (serious-condition (condition) condition)))
                :name "store-guard-attribution-holder")))
        (sb-thread:wait-on-semaphore holding)
        (ethereum-lisp.telemetry:telemetry-call-with-wait-accounting
         (lambda ()
           (let ((ethereum-lisp.telemetry:*telemetry-activity-label*
                   "engine_newPayloadV4"))
             (is (eq :engine (funcall priority (lambda () :engine)))))
           (let* ((fields (ethereum-lisp.telemetry:telemetry-wait-fields))
                  (waited (cdr (assoc "guardWaitMs" fields :test #'string=)))
                  (holders (cdr (assoc "guardWaitedFor" fields
                                       :test #'string=))))
             (is (and waited (<= 250 waited)))
             (is (and holders
                      (eql 0 (search "sync-gap-fill:" holders))
                      (search "+" holders))))))
        (sb-thread:join-thread holder)
        (is (equal '("sync-gap-fill") long-holds))))))

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
