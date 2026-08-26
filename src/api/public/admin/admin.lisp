(in-package #:ethereum-lisp.public-api)

;;;; The admin namespace: what this node is, who it is connected to, and adding
;;;; a peer by hand.
;;;;
;;;; Peering state lives several layers below the RPC surface, and this layer is
;;;; not allowed to know about sockets or listeners. So it reaches them through
;;;; a backend of closures, the same shape the eth-sync layer uses to reach the
;;;; chain — one struct threaded through the dispatch chain rather than five
;;;; separate parameters.
;;;;
;;;; A node with no backend answers admin methods as unavailable rather than
;;;; inventing values, and reports itself as not listening. That is also the
;;;; honest answer, because a node built without peering is not listening.

(defstruct (admin-backend
            (:constructor make-admin-backend
                (&key node-info peers add-peer remove-peer
                      peer-count listening-p syncing)))
  "How the RPC layer reaches peering state, as closures.

NODE-INFO returns a plist describing this node; PEERS a list of plists, one per
connected peer; ADD-PEER takes an enode URL and returns true if it was accepted;
PEER-COUNT an integer; LISTENING-P whether an inbound listener is bound; SYNCING
returns the latest consistent eth_syncing snapshot. Any may be NIL, which reads
as 'this node cannot answer that'."
  node-info
  peers
  add-peer
  remove-peer
  peer-count
  listening-p
  syncing)

(defun admin-backend-listening (backend)
  (and backend
       (admin-backend-listening-p backend)
       (funcall (admin-backend-listening-p backend))
       t))

(defun admin-backend-peer-total (backend)
  (or (and backend
           (admin-backend-peer-count backend)
           (funcall (admin-backend-peer-count backend)))
      0))

(defun admin-unavailable-fail (method)
  (block-validation-fail
   (format nil "~A is unavailable because this node has no peering backend"
           method)))

(defun admin-peer-protocols-object (peer)
  "The `protocols` object of a PeerInfo.

The eth version is the one THIS session negotiated, never a global constant:
+eth-protocol-version+ is bound in two packages to two different numbers, and a
peer's version is a property of its connection anyway."
  `(("eth" . ,(let ((version (getf peer :eth-version)))
                (if version
                    `(("version" . ,version))
                    nil)))))

(defun admin-peer-object (peer)
  `(("id" . ,(getf peer :enode-id))
    ("name" . ,(or (getf peer :client-id) ""))
    ("enode" . ,(getf peer :enode))
    ("network" .
     (("localAddress" . ,(getf peer :local-address))
      ("remoteAddress" . ,(getf peer :remote-address))
      ("inbound" . ,(if (eq :inbound (getf peer :direction)) t :false))))
    ("protocols" . ,(admin-peer-protocols-object peer))))

(defun engine-rpc-handle-admin-node-info (params backend)
  (when params
    (block-validation-fail "admin_nodeInfo params must be empty"))
  (unless (and backend (admin-backend-node-info backend))
    (admin-unavailable-fail "admin_nodeInfo"))
  (let ((info (funcall (admin-backend-node-info backend))))
    `(("id" . ,(getf info :enode-id))
      ("name" . ,(or (getf info :client-id) ""))
      ("enode" . ,(getf info :enode))
      ("ip" . ,(getf info :ip))
      ;; Only the ports we actually bind are reported. Discovery has no
      ;; listening socket of its own yet, so its port is reported as 0 rather
      ;; than as a port nothing is behind.
      ("ports" . (("discovery" . 0)
                  ("listener" . ,(or (getf info :listener-port) 0))))
      ("listenAddr" . ,(getf info :listen-address))
      ("protocols" .
       (("eth" . ,(let ((eth (getf info :eth)))
                    (if eth
                        `(("network" . ,(getf eth :network-id))
                          ("genesis" . ,(getf eth :genesis))
                          ("head" . ,(getf eth :head)))
                        nil))))))))

(defun engine-rpc-handle-admin-peers (params backend)
  (when params
    (block-validation-fail "admin_peers params must be empty"))
  (unless (and backend (admin-backend-peers backend))
    (admin-unavailable-fail "admin_peers"))
  ;; A vector is an unambiguous JSON array, including when there are no peers;
  ;; NIL is JSON null at the writer boundary.
  (coerce (mapcar #'admin-peer-object
                  (funcall (admin-backend-peers backend)))
          'vector))

(defun engine-rpc-handle-admin-add-peer (params backend)
  (unless (= 1 (length params))
    (invalid-parameters-fail "admin_addPeer params must contain one enode URL"))
  (unless (and backend (admin-backend-add-peer backend))
    (admin-unavailable-fail "admin_addPeer"))
  (let ((enode (first params)))
    (unless (stringp enode)
      (invalid-parameters-fail "admin_addPeer enode must be a string"))
    ;; Parsed here so a malformed enode is a parameter error rather than a
    ;; failure inside a worker thread that nobody is watching.
    (parse-enode-url enode)
    (if (funcall (admin-backend-add-peer backend) enode) t :false)))

(defun engine-rpc-handle-admin-remove-peer (params backend)
  (unless (= 1 (length params))
    (invalid-parameters-fail
     "admin_removePeer params must contain one enode URL"))
  (unless (and backend (admin-backend-remove-peer backend))
    (admin-unavailable-fail "admin_removePeer"))
  (let ((enode (first params)))
    (unless (stringp enode)
      (invalid-parameters-fail "admin_removePeer enode must be a string"))
    (parse-enode-url enode)
    (if (funcall (admin-backend-remove-peer backend) enode) t :false)))

(defun engine-rpc-handle-public-admin-method (context)
  (let ((params (public-rpc-dispatch-context-params context))
        (backend (public-rpc-dispatch-context-admin-backend context)))
    (cond
      ((public-rpc-dispatch-method-p context "admin_nodeInfo")
       (public-rpc-dispatch-response
        context (engine-rpc-handle-admin-node-info params backend)))
      ((public-rpc-dispatch-method-p context "admin_peers")
       (public-rpc-dispatch-response
        context (engine-rpc-handle-admin-peers params backend)))
      ((public-rpc-dispatch-method-p context "admin_addPeer")
       (public-rpc-dispatch-response
        context (engine-rpc-handle-admin-add-peer params backend)))
      ((public-rpc-dispatch-method-p context "admin_removePeer")
       (public-rpc-dispatch-response
        context (engine-rpc-handle-admin-remove-peer params backend)))
      (t nil))))
