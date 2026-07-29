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
      (let ((peer (first peers)))
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
