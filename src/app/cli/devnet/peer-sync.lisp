(in-package #:ethereum-lisp.cli)

;;;; Outbound peer sync.
;;;;
;;;; When the node is started with one or more --peer enode://… URLs, a
;;;; background worker dials each in turn, completes the RLPx + eth handshake,
;;;; and downloads the peer's chain into the node's store over the eth wire
;;;; protocol. Imports run under the node's store guard so they do not race the
;;;; RPC and dev-period workers that share the single store. A peer that is
;;;; unreachable or incompatible is logged and skipped rather than taking the
;;;; node down.

(defun devnet-peer-sync-import-block (node block)
  "Execute, commit, and canonicalize BLOCK into NODE's store under the store
guard, so a downloaded block is immediately visible to the RPC services."
  (let ((store (devnet-node-store node))
        (config (devnet-node-config node)))
    (call-with-devnet-node-store-guard
     node
     (lambda ()
       (execute-and-commit-engine-payload store block config)
       (chain-store-set-canonical-head store (block-hash block)
                                       :chain-config config)))))

(defun devnet-peer-sync-status (node)
  "Return (VALUES STATUS HEAD-NUMBER): our eth Status built from NODE's current
head, and that head number. Store hashes are hash32 objects; the Status wants
raw bytes, so genesis and best hashes are converted with hash32-bytes. The head
reads run under the store guard, since the store is shared with the RPC and
dev-period workers and its hash tables are not internally synchronized."
  (let* ((store (devnet-node-store node))
         (config (devnet-node-config node))
         (genesis-block (devnet-node-genesis-block node))
         (genesis-timestamp (block-header-timestamp (block-header genesis-block))))
    (multiple-value-bind (head-number head-timestamp genesis-hash best-hash)
        (call-with-devnet-node-store-guard
         node
         (lambda ()
           (let ((head-number (chain-store-head-number store)))
             ;; chain-store-latest-block is the canonical block at the head
             ;; number (genesis before any sync); chain-store-head-block is the
             ;; forkchoice head, unset until a consensus client drives
             ;; forkchoiceUpdated.
             (values head-number
                     (block-header-timestamp
                      (block-header (chain-store-latest-block store)))
                     (hash32-bytes (chain-store-canonical-hash store 0))
                     (hash32-bytes (chain-store-canonical-hash store head-number))))))
      (values (eth-build-status config genesis-hash head-number head-timestamp
                                best-hash
                                (or (chain-config-terminal-total-difficulty config) 0)
                                ;; Advertise the operator's network id (which may
                                ;; differ from the chain id via --networkid).
                                :network-id (devnet-node-network-id node)
                                :genesis-timestamp genesis-timestamp)
              head-number))))

(defun devnet-peer-sync-one (node enode private-key)
  "Dial ENODE, complete the handshake, and download its chain into NODE's store
starting just past our current head. Returns the number of blocks imported."
  (multiple-value-bind (node-id host tcp-port discovery-port)
      (parse-enode-url enode)
    (declare (ignore discovery-port))
    (multiple-value-bind (status head-number) (devnet-peer-sync-status node)
      (telemetry-log :info "peer.sync.dialing"
                     :fields (list (cons "enode" enode) (cons "host" host))
                     :sink (devnet-node-telemetry-sink node))
      (multiple-value-bind (peer socket)
          (eth-sync-connect-peer host tcp-port node-id private-key status)
        (unwind-protect
             (let ((count (eth-sync-download-blocks
                           peer
                           (lambda (block)
                             (devnet-peer-sync-import-block node block))
                           :start-number (1+ head-number))))
               (telemetry-log :info "peer.sync.completed"
                              :fields (list (cons "enode" enode)
                                            (cons "blocks" (princ-to-string count)))
                              :sink (devnet-node-telemetry-sink node))
               count)
          ;; Tell the peer we are done before dropping the connection, then
          ;; close the socket the dialer handed us. The argument is a devp2p
          ;; disconnect REASON, not a message id.
          (ignore-errors
           (rlpx-send-disconnect (eth-peer-connection peer)
                                 +devp2p-disconnect-requested+))
          (ignore-errors (sb-bsd-sockets:socket-close socket)))))))

(defun devnet-start-peer-sync-thread (node shutdown-controller error-callback)
  "Start the outbound peer-sync worker, or return NIL when no peers are
configured (or off SBCL). Dials each configured enode once; a per-peer failure
is logged and skipped, and only an error escaping that is fail-stop."
  #-sbcl
  (declare (ignore node shutdown-controller error-callback))
  #-sbcl
  nil
  #+sbcl
  (let ((peers (devnet-node-peers node)))
    (when peers
      (sb-thread:make-thread
       (lambda ()
         (handler-case
             (let ((private-key (secp256k1-random-private-key)))
               (dolist (enode peers)
                 (when (devnet-shutdown-requested-p shutdown-controller)
                   (return))
                 (handler-case
                     (devnet-peer-sync-one node enode private-key)
                   (error (condition)
                     (telemetry-log
                      :warning "peer.sync.peer_failed"
                      :fields (list (cons "enode" enode)
                                    (cons "error" (princ-to-string condition)))
                      :sink (devnet-node-telemetry-sink node))))))
           (error (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-peer-sync"))))
