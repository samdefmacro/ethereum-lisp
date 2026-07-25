(in-package #:ethereum-lisp.cli)

;;;; Outbound peer sync.
;;;;
;;;; When the node is started with one or more --peer enode://… URLs, a
;;;; background worker dials each in turn, completes the RLPx + eth handshake,
;;;; and downloads the peer's chain into the node's store over the eth wire
;;;; protocol. The connection is not one-way: the peer's own header, body, and
;;;; receipt requests are answered from our store over the same session. Imports
;;;; and reads run under the node's store guard so they do not race the RPC and
;;;; dev-period workers that share the single store. A peer that is unreachable
;;;; or incompatible is logged and skipped rather than taking the node down.

(defun devnet-peer-txpool-policy (node)
  "The admission policy gossiped transactions face, which is the one
eth_sendRawTransaction applies. A transaction from a peer is remote, so it earns
the local exemptions only if its sender is one of the configured local
addresses — the same rule go-ethereum's --txpool.locals uses."
  (make-txpool-admission-policy
   :allow-unprotected-transactions-p
   (devnet-node-allow-unprotected-transactions-p node)
   :price-limit (devnet-node-txpool-price-limit node)
   :price-bump-percent (devnet-node-txpool-price-bump-percent node)
   :account-slot-limit (devnet-node-txpool-account-slot-limit node)
   :global-slot-limit (devnet-node-txpool-global-slot-limit node)
   :account-queue-limit (devnet-node-txpool-account-queue-limit node)
   :global-queue-limit (devnet-node-txpool-global-queue-limit node)
   :local-addresses (devnet-node-txpool-local-addresses node)
   :no-local-exemptions-p (devnet-node-txpool-no-local-exemptions-p node)))

(defun devnet-peer-serve-backend (node)
  "A serve backend answering a peer's requests and gossip from NODE's store.

Each lookup takes the store guard on its own rather than holding it across a
whole query, so a peer asking for a thousand headers cannot stall the RPC
services. A query may then span a store that moved underneath it, which is
harmless: every block it returns was a real block of ours, and the peer
validates what it receives regardless. Admitting a gossiped transaction does
take the guard for the whole admission, since that mutates the pool."
  (let ((store (devnet-node-store node))
        (config (devnet-node-config node))
        (policy (devnet-peer-txpool-policy node)))
    (flet ((guarded (thunk)
             (call-with-devnet-node-store-guard node thunk)))
      (make-eth-serve-backend
       :block-by-number
       (lambda (number)
         (guarded (lambda () (chain-store-block-by-number store number))))
       :block-by-hash
       (lambda (hash)
         (guarded (lambda ()
                    ;; The store keys blocks by hash32; the wire carries bytes.
                    (chain-store-known-block store (make-hash32 hash)))))
       :pooled-transaction
       (lambda (hash)
         (guarded (lambda ()
                    (engine-payload-store-pooled-transaction
                     store (make-hash32 hash)))))
       :known-transaction-p
       (lambda (hash)
         (guarded (lambda ()
                    (let ((key (make-hash32 hash)))
                      ;; Already pooled, or already mined into our chain.
                      (or (and (engine-payload-store-pooled-transaction store key)
                               t)
                          (and (chain-store-transaction-location store key) t))))))
       :accept-transaction
       (lambda (transaction)
         (guarded (lambda ()
                    (txpool-admit-transaction
                     transaction store config policy
                     :admitted-at (unix-time)))))))))

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
              head-number
              (make-eth-chain-context config genesis-hash head-number
                                      head-timestamp genesis-timestamp)))))

(defun devnet-peer-fetch-gossiped-transactions (node peer enode)
  "Fetch what PEER announced during the sync, and return how many the pool took.

A peer that announces and then will not deliver is a peer problem, not ours, so
a failure here is logged and the sync still counts as completed."
  (handler-case (eth-peer-fetch-announced-transactions peer)
    (error (condition)
      (telemetry-log :warning "peer.gossip.fetch_failed"
                     :fields (list (cons "enode" enode)
                                   (cons "error" (princ-to-string condition)))
                     :sink (devnet-node-telemetry-sink node))
      0)))

(defun devnet-peer-sync-one (node enode private-key)
  "Dial ENODE, complete the handshake, and download its chain into NODE's store
starting just past our current head. Returns the number of blocks imported."
  (multiple-value-bind (node-id host tcp-port discovery-port)
      (parse-enode-url enode)
    (declare (ignore discovery-port))
    (multiple-value-bind (status head-number chain-context)
        (devnet-peer-sync-status node)
      (telemetry-log :info "peer.sync.dialing"
                     :fields (list (cons "enode" enode) (cons "host" host))
                     :sink (devnet-node-telemetry-sink node))
      (multiple-value-bind (peer socket)
          (eth-sync-connect-peer host tcp-port node-id private-key status
                                 :chain-context chain-context
                                 :serve-backend (devnet-peer-serve-backend node))
        (unwind-protect
             (let ((count (eth-sync-download-blocks
                           peer
                           (lambda (block)
                             (devnet-peer-sync-import-block node block))
                           :start-number (1+ head-number))))
               ;; Transactions the peer pushed whole were admitted as they
               ;; arrived; ones it only announced are fetched now, since that
               ;; waits for a reply and so cannot run inside the download.
               (let ((gossiped (devnet-peer-fetch-gossiped-transactions
                                node peer enode)))
                 (telemetry-log
                  :info "peer.sync.completed"
                  :fields (list (cons "enode" enode)
                                (cons "blocks" (princ-to-string count))
                                (cons "transactions" (princ-to-string gossiped)))
                  :sink (devnet-node-telemetry-sink node)))
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
             ;; Use the node's stable identity, not a throwaway key, and claim
             ;; each peer so it is not also dialed by the discovery worker.
             (let ((private-key (devnet-node-node-key node)))
               (dolist (enode peers)
                 (when (devnet-shutdown-requested-p shutdown-controller)
                   (return))
                 (let ((node-id (nth-value 0 (parse-enode-url enode))))
                   (when (devnet-node-claim-dial node node-id)
                     (handler-case
                         (devnet-peer-sync-one node enode private-key)
                       (error (condition)
                         ;; Release so a transiently-failed peer can be retried.
                         (devnet-node-release-dial node node-id)
                         (telemetry-log
                          :warning "peer.sync.peer_failed"
                          :fields (list (cons "enode" enode)
                                        (cons "error" (princ-to-string condition)))
                          :sink (devnet-node-telemetry-sink node))))))))
           (error (condition)
             (funcall error-callback condition)
             (devnet-shutdown-request shutdown-controller))))
       :name "ethereum-lisp-devnet-peer-sync"))))
