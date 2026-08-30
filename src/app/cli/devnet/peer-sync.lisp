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

(defun devnet-pooled-blob-sidecar (store transaction)
  "Reassemble a version-1 network sidecar for pooled blob TRANSACTION."
  (let ((entries
          (loop for hash in
                  (blob-transaction-blob-versioned-hashes transaction)
                for entry =
                  (engine-payload-store-blob-and-proofs-v2 store hash)
                unless entry do (return nil)
                collect entry)))
    (when entries
      (make-blob-sidecar
       :blobs (mapcar #'engine-blob-and-proofs-blob entries)
       :commitments (mapcar #'engine-blob-and-proofs-commitment entries)
       :proofs (loop for entry in entries
                     append
                     (engine-blob-and-proofs-cell-proofs entry))))))

(defun devnet-peer-custody-indices (mask)
  "Decode geth's little-endian 128-bit eth/72 custody bitmap."
  (loop for byte across (ensure-byte-vector mask)
        for byte-index from 0
        append
        (loop for bit below 8
              when (logbitp bit byte)
                collect (+ (* byte-index 8) bit))))

(defun devnet-peer-blob-cells-from-reader
    (reader hashes mask &key (cell-function #'kzg-compute-cells-and-proofs))
  "Serve geth-compatible flat cell groups from a SIDECAR READER.

READER receives a transaction hash and returns a validated full blob sidecar or
NIL. CELL-FUNCTION is injectable so selection, grouping, and custody semantics
can be tested without making cryptographic capability a test precondition."
  (let ((indices (devnet-peer-custody-indices mask))
        (response-hashes '())
        (groups '())
        (cell-count 0)
        (maximum-cells (floor +eth-soft-response-limit+ +bytes-per-cell+)))
    (dolist (hash hashes)
      (when (>= cell-count maximum-cells)
        (return))
      (let ((sidecar (funcall reader hash)))
        (when sidecar
          (let ((flat
                  (loop for blob in (blob-sidecar-blobs sidecar)
                        append
                        (multiple-value-bind (cells proofs)
                            (funcall cell-function blob)
                          (declare (ignore proofs))
                          (mapcar (lambda (index) (nth index cells)) indices)))))
            ;; geth omits a transaction when the requested mask selects no
            ;; cells, and permits the final group to cross the soft limit.
            (when flat
              (push (copy-seq hash) response-hashes)
              (push flat groups)
              (incf cell-count (length flat)))))))
    (values (nreverse response-hashes) (nreverse groups) (copy-seq mask))))

(defun devnet-peer-blob-cells (guarded store hashes mask)
  "Resolve pooled sidecars under GUARDED, then compute eth/72 cell groups."
  (devnet-peer-blob-cells-from-reader
   (lambda (hash)
     (funcall
      guarded
      (lambda ()
        (let ((transaction
                (engine-payload-store-pooled-transaction
                 store (make-hash32 hash))))
          (and (typep transaction 'blob-transaction)
               (devnet-pooled-blob-sidecar store transaction))))))
   hashes mask))

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
       :pooled-blob-sidecar
       (lambda (transaction)
         (guarded
          (lambda () (devnet-pooled-blob-sidecar store transaction))))
       :blob-cells
       (when (kzg-cell-computation-available-p)
         (lambda (hashes mask)
           (devnet-peer-blob-cells #'guarded store hashes mask)))
       :known-transaction-p
       (lambda (hash)
         (guarded (lambda ()
                    (let ((key (make-hash32 hash)))
                      ;; Already pooled, or already mined into our chain.
                      (or (and (engine-payload-store-pooled-transaction store key)
                               t)
                          (and (chain-store-transaction-location store key) t))))))
       ;; Pinned geth drops inbound Transactions, pooled-transaction replies,
       ;; and hash announcements before decoding until its chain is fresh. The
       ;; coordinator's claim is our authoritative active-catch-up boundary.
       ;; Read it under the peer-table mutex, before taking the store guard, so
       ;; public tx gossip cannot contend with SNAP persistence.
       :accept-transactions-p
       (lambda ()
         (call-with-devnet-peer-table
          node (lambda () (not (devnet-node-syncing-p node)))))
       :accept-transaction
       (lambda (transaction)
         (guarded (lambda ()
                    (txpool-admit-transaction
                     transaction store config policy
                     :admitted-at (unix-time)))))
       :accept-blob-sidecar
       (lambda (sidecar)
         (guarded
          (lambda () (engine-payload-store-put-blob-sidecar store sidecar))))
       :accept-block
       (lambda (block)
         ;; Downloaded and propagated blocks share the exact same conversion,
         ;; validation, execution, and durable candidate path.  In particular,
         ;; this does not publish a peer tip as canonical.
         (devnet-peer-sync-import-block node block))))))

(defun devnet-peer-snap-backend (node)
  "Build a guarded snap server for NODE's current durable canonical state.

Only the direct database provider has the content-addressed trie/code backing
needed to answer every request without materialising the world state. Returning
NIL keeps snap out of Hello on other backends."
  (let ((store (devnet-node-store node)))
    (unless (database-engine-payload-store-p store)
      (return-from devnet-peer-snap-backend nil))
    (call-with-devnet-node-store-guard
     node
     (lambda ()
       (let* ((head (chain-store-head-block store))
              (head-hash (and head (block-hash head)))
              (state (and head-hash (chain-store-state-db store head-hash))))
         (unless state
           (return-from devnet-peer-snap-backend nil))
         (let ((backend
                 (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                  (database-engine-payload-store-database store) state)))
           (ethereum-lisp.snap:make-snap-state-backend
            :account-range
            (lambda (request)
              (call-with-devnet-node-store-guard
               node
               (lambda ()
                 (funcall
                  (ethereum-lisp.snap:snap-state-backend-account-range backend)
                  request))))
            :storage-ranges
            (lambda (request)
              (call-with-devnet-node-store-guard
               node
               (lambda ()
                 (funcall
                  (ethereum-lisp.snap:snap-state-backend-storage-ranges backend)
                  request))))
            :bytecodes
            (lambda (request)
              (call-with-devnet-node-store-guard
               node
               (lambda ()
                 (funcall
                  (ethereum-lisp.snap:snap-state-backend-bytecodes backend)
                  request))))
            :trie-nodes
            (lambda (request)
              (call-with-devnet-node-store-guard
               node
               (lambda ()
                 (funcall
                  (ethereum-lisp.snap:snap-state-backend-trie-nodes backend)
                  request)))))))))))

(defconstant +devnet-broadcast-batch-limit+ 64
  "How many transactions we push to one peer in a single tick. Our policy: a
bound on how much one pass can put on the wire, not a target.")

(defconstant +devnet-peer-known-transaction-limit+ 8192
  "How many transaction hashes we remember having sent a peer. Our policy. Past
this the set is cleared rather than grown -- the cost of re-sending a
transaction a peer already has is one wasted message, while an unbounded set is
a leak that lasts as long as the session.")

(defun devnet-peer-pending-chain-update (node peer)
  "Return a sole-writer closure announcing each new canonical head once."
  (let ((last-number nil)
        (last-hash nil))
    (lambda ()
      (multiple-value-bind (snapshot ran-p)
          (call-with-devnet-node-store-guard-if-free
           node
           (lambda ()
             (let* ((store (devnet-node-store node))
                    (number (chain-store-head-number store))
                    (hash (chain-store-canonical-hash store number)))
               (and hash (list number hash)))))
        (when (and ran-p snapshot
                   (or (null last-number)
                       (/= last-number (first snapshot))
                       (not (hash32= last-hash (second snapshot)))))
          (let ((number (first snapshot))
                (hash (second snapshot)))
            (lambda ()
              ;; eth/69 replaced the legacy NewBlockHashes/NewBlock
              ;; propagation path with BlockRangeUpdate.  Current geth keeps
              ;; the old numeric constants but deliberately has no handlers
              ;; for them, so sending both makes a conforming eth/69+ peer
              ;; disconnect with a subprotocol error.  Retain the legacy
              ;; announcement only for the eth/68 capability we still expose.
              (if (>= (eth-peer-eth-version peer) +eth-protocol-version-69+)
                  (eth-peer-send-block-range-update
                   peer 0 number (hash32-bytes hash))
                  (eth-peer-send
                   peer +eth-message-new-block-hashes+
                   (encode-eth-new-block-hashes
                    (list (make-eth-new-block-hash
                           (hash32-bytes hash) number)))))
              (setf last-number number
                    last-hash hash))))))))

(defun devnet-peer-pending-broadcast (node)
  "A closure returning the transactions this peer has not been sent yet.

THIS IS THE SEAM THAT MAKES US A CONTRIBUTOR RATHER THAN A CONSUMER: without it
a transaction submitted to our RPC reaches no one, and our pool only ever drains
into blocks we build ourselves.

It consumes the txpool's independent bounded change log.  This does not share
the journal exporter's dirty-key set, so journaling and every peer have separate
cursors.  Falling behind the bound triggers one full pooled snapshot.

The known set is per session and bounded; clearing it on overflow re-sends at
worst, which a peer discards.

Returns a CLOSURE because the session loop is the only thread allowed to write
to its connection: outbound work has to arrive as data for that loop to send,
never as another thread sending on the peer."
  (let ((store (devnet-node-store node))
        (known (make-hash-table :test #'equalp))
        (cursor 0)
        ;; CURSOR may advance past more changes than one wire tick can carry,
        ;; so retain the decoded entries locally until every one has been
        ;; offered.  The txpool and its change log are bounded; consequently
        ;; this per-peer queue is bounded by the same admission policy.
        (pending '()))
    (lambda ()
      (when (null pending)
        (multiple-value-bind (transactions next-cursor)
            (call-with-devnet-node-store-guard
             node
             (lambda ()
               (multiple-value-bind (hashes current overflow-p)
                   (engine-payload-store-txpool-changes-since store cursor)
                 (let ((transactions
                         (if overflow-p
                             (engine-payload-store-pooled-transactions store)
                             (remove
                              nil
                              (mapcar
                               (lambda (hash)
                                 (engine-payload-store-pooled-transaction
                                  store hash))
                               hashes)))))
                   (values
                    (remove
                     nil
                     (mapcar
                      (lambda (transaction)
                        (if (typep transaction 'blob-transaction)
                            (let ((sidecar
                                    (devnet-pooled-blob-sidecar
                                     store transaction)))
                              (and sidecar (cons transaction sidecar)))
                            transaction))
                      transactions))
                    current)))))
          ;; Advance only after every changed hash has been resolved while the
          ;; store is guarded.  Entries beyond this tick remain in PENDING;
          ;; advancing without that queue was the burst-loss bug.
          (setf pending transactions
                cursor next-cursor)))
      (let ((fresh '()))
        (loop while (and pending
                         (< (length fresh) +devnet-broadcast-batch-limit+))
              for entry = (pop pending)
              for transaction = (eth-pooled-entry-transaction entry)
              for hash = (hash32-bytes (transaction-hash transaction))
              unless (gethash hash known)
                do (when (>= (hash-table-count known)
                             +devnet-peer-known-transaction-limit+)
                     (clrhash known))
                   (setf (gethash hash known) t)
                   (push entry fresh))
        (nreverse fresh)))))

(defun devnet-peer-new-payload-version (block config)
  "Select the Engine newPayload version required by BLOCK's active fork."
  (let* ((header (block-header block))
         (number (block-header-number header))
         (timestamp (block-header-timestamp header)))
    (cond
      ((chain-config-amsterdam-p config number timestamp) 5)
      ((or (chain-config-prague-p config number timestamp)
           (chain-config-osaka-p config number timestamp))
       4)
      ((chain-config-cancun-p config number timestamp) 3)
      ((chain-config-shanghai-p config number timestamp) 2)
      (t 1))))

(defun devnet-peer-block-versioned-hashes (block)
  "Return BLOCK's EIP-4844 versioned hashes in transaction order."
  (loop for transaction in (block-transactions block)
        append (coerce (transaction-blob-versioned-hashes transaction) 'list)))

(defun devnet-peer-block-executable-inputs (block config)
  "Return Engine adapter metadata for a peer-supplied BLOCK.

This keeps fork-to-newPayload V1--V5 selection and typed-to-Engine conversion
testable at the ingress adapter.  Actual eth BlockBodies admission stays typed:
Prague execution requests and Amsterdam block access lists are execution side
data absent from the wire body, so reconstructing a block from this envelope
would replace committed data with NIL."
  (let* ((version (devnet-peer-new-payload-version block config))
         (envelope (block-to-executable-data block))
         (header (block-header block)))
    (values version
            (execution-payload-envelope-execution-payload envelope)
            (block-header-parent-beacon-root header)
            (devnet-peer-block-versioned-hashes block)
            (execution-payload-envelope-requests envelope)
            (>= version 3)
            (>= version 4))))

(define-condition devnet-peer-sync-invalid (block-validation-error) ()
  (:documentation
   "A peer range executed to a durable deterministic INVALID verdict.

The verdict is already installed in the payload store and, when configured,
persisted before this condition is signaled.  Sync coordinators may therefore
stop the rejected branch without treating it as a node-fatal implementation or
storage failure; subsequent Engine requests can read the cached verdict."))

(defun devnet-peer-sync-import-block
    (node block &key peer-id require-valid-p invalid-head-hash)
  "Import BLOCK as a validated, durable, noncanonical candidate.

PEER-ID, when supplied by a forward downloader, is recorded in the same
database batch as the candidate so a restarted session resumes after this
block.  Gap-fill and propagation imports omit it because they are not a
contiguous forward cursor. REQUIRE-VALID-P rejects a deterministic INVALID
verdict; ACCEPTED and SYNCING remain successful durable-buffering outcomes.
Those statuses are expected while SNAP has not yet made the candidate's parent
state executable, and treating them as peer invalidity would terminate a normal
forward download before state import can close the gap.  INVALID-HEAD-HASH
binds a deterministic bad ancestor to the bounded Engine/CL target whose
backfill discovered it, so Engine can answer INVALID even when later descendant
bodies were never admitted after the downloader stopped at the bad block."
  (let ((store (devnet-node-store node))
        (config (devnet-node-config node))
        (durability-function
          (devnet-node-candidate-persistence-function node)))
    (call-with-devnet-node-store-guard
     node
     (lambda ()
       ;; Exercise the same fork/version adapter used by Engine RPC without
       ;; round-tripping the canonical eth body through a representation that
       ;; cannot carry derived requests/BAL side data.
       (devnet-peer-block-executable-inputs block config)
       (let ((progress
               (and
                peer-id
                durability-function
                (make-node-store-peer-sync-progress
                 :peer-id (if (stringp peer-id)
                              (node-id-from-hex peer-id)
                              peer-id)
                 :authority-id
                 (devnet-persistence-state-authority-id
                  (devnet-node-persistence-state node))
                 :chain-id (chain-config-chain-id config)
                 :genesis-hash
                 (block-hash (devnet-node-genesis-block node))
                 :last-number
                 (block-header-number (block-header block))
                 :last-hash (block-hash block)))))
         (multiple-value-bind (status candidate receipts)
             (apply
              #'import-p2p-block-candidate
              store block config
              (append
               (list :durability-function durability-function
                     :invalid-head-hash invalid-head-hash)
               (when progress (list :progress progress))))
           (when (and require-valid-p
                      (string= +payload-status-invalid+
                               (payload-status-status status)))
             (error
              'devnet-peer-sync-invalid
              :message
              (format
               nil "Peer range block ~A was invalid: ~A~@[ (~A)~]"
               (hash32-to-hex (block-hash block))
               (payload-status-status status)
               (payload-status-validation-error status))))
           (values status candidate receipts)))))))

(defun devnet-peer-sync-status (node)
  "Return STATUS, HEAD-NUMBER, CHAIN-CONTEXT, and canonical HEAD-HASH.

The status is built from NODE's current canonical head. Store hashes are
hash32 objects; the Status wants
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
                                      head-timestamp genesis-timestamp)
              (make-hash32 best-hash)))))

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

(defun devnet-node-reset-peer-sync-progress-without-guard (node peer-id)
  "Delete PEER-ID's cursor while the caller holds NODE's store guard."
  (let ((reset (devnet-node-peer-sync-progress-reset-function node)))
    (unless reset
      (block-validation-fail
       "Peer sync cursor branch changed but no durable reset is available"))
    (funcall reset peer-id)))

(defun devnet-node-reset-peer-sync-progress (node peer-id)
  "Atomically delete PEER-ID's cursor after either side abandons its branch."
  (call-with-devnet-node-store-guard
   node
   (lambda ()
     (devnet-node-reset-peer-sync-progress-without-guard node peer-id))))

(defun devnet-node-peer-sync-resume-point
    (node peer-id canonical-number canonical-hash)
  "Return START-NUMBER and EXPECTED-PARENT-HASH for PEER-ID.

A cursor behind a newly published canonical view is obsolete; one at the same
height remains usable only when it names that exact canonical hash. A cursor
ahead is usable only when its candidate and executed state are both durable and
it still descends from that canonical view. Corrupt cursor targets fail closed
instead of silently replaying from genesis."
  (let ((reader (devnet-node-peer-sync-progress-function node)))
    (if (null reader)
        (values (1+ canonical-number) canonical-hash nil)
        (call-with-devnet-node-store-guard
         node
         (lambda ()
           ;; The cursor read, branch decision, candidate verification, and a
           ;; possible durable delete share the same node guard. Otherwise an
           ;; FCU/import could install a newer cursor between read and reset.
           (multiple-value-bind (progress present-p)
               (funcall reader peer-id)
             (if (not present-p)
                 (values (1+ canonical-number) canonical-hash nil)
                 (let ((number
                         (node-store-peer-sync-progress-last-number progress))
                       (hash
                         (node-store-peer-sync-progress-last-hash progress)))
                   (if (or (< number canonical-number)
                           (and (= number canonical-number)
                                (not (hash32= hash canonical-hash))))
                       (progn
                         (devnet-node-reset-peer-sync-progress-without-guard
                          node peer-id)
                         (values (1+ canonical-number) canonical-hash nil))
                       (let* ((store (devnet-node-store node))
                              (candidate (chain-store-known-block store hash)))
                         (unless (and candidate
                                      (= number
                                         (block-header-number
                                          (block-header candidate)))
                                      (chain-store-state-available-p store hash))
                           (block-validation-fail
                            "Peer sync cursor does not name a durable executed candidate"))
                         (if (and (> number canonical-number)
                                  (not
                                   (engine-payload-store-ancestor-p
                                    store canonical-hash hash)))
                             (progn
                               ;; This cursor names completed work only on an
                               ;; abandoned branch. Remove it durably before
                               ;; starting at the new canonical anchor; the
                               ;; replacement is installed with the first new
                               ;; candidate in one WAL batch.
                               (devnet-node-reset-peer-sync-progress-without-guard
                                node peer-id)
                               (values
                                (1+ canonical-number) canonical-hash nil))
                             (values (1+ number) hash
                                     (> number canonical-number)))))))))))))

(defun devnet-peer-download-from-resume
    (node peer peer-id canonical-number canonical-hash)
  "Download from PEER's durable cursor, rebasing once on a peer-side reorg.

An anchor mismatch happens before the downloader imports a block.  When the
anchor came from an ahead-of-canonical peer cursor, delete that cursor durably
and retry exactly once from the local canonical anchor.  A second mismatch, or
a mismatch of the canonical anchor itself, is a peer delivery failure and is
allowed to escape."
  (labels ((download (start-number expected-parent-hash)
             (eth-sync-download-blocks
              peer
              (lambda (block)
                (devnet-peer-sync-import-block
                 node block :peer-id peer-id :require-valid-p t))
              :start-number start-number
              :expected-parent-hash expected-parent-hash))
           (peer-has-cursor-p (number hash)
             (let ((headers
                     (eth-peer-get-block-headers
                      peer :origin-number number :amount 1)))
               (and (= 1 (length headers))
                    (= number
                       (block-header-number (first headers)))
                    (hash32= hash
                             (block-header-hash (first headers)))))))
    (multiple-value-bind
          (start-number expected-parent-hash cursor-anchor-p)
        (devnet-node-peer-sync-resume-point
         node peer-id canonical-number canonical-hash)
      ;; A peer can reorg to a tip at or below the old cursor.  In that case a
      ;; range request at cursor+1 merely returns empty and never produces the
      ;; first-header mismatch below.  Probe that height on the peer's canonical
      ;; chain before trusting the cursor. A hash-origin lookup is insufficient:
      ;; a normal peer may retain the abandoned side-chain header indefinitely.
      (when (and cursor-anchor-p
                 (not (peer-has-cursor-p
                       (1- start-number) expected-parent-hash)))
        (devnet-node-reset-peer-sync-progress node peer-id)
        (setf start-number (1+ canonical-number)
              expected-parent-hash canonical-hash
              cursor-anchor-p nil))
      (handler-case
          (download start-number expected-parent-hash)
        (eth-sync-anchor-mismatch (condition)
          (unless cursor-anchor-p
            (error condition))
          (devnet-node-reset-peer-sync-progress node peer-id)
          (download (1+ canonical-number) canonical-hash))))))

(defun devnet-peer-sync-one (node enode private-key)
  "Dial ENODE, complete the handshake, and download its chain into NODE's store
starting just past our current head. Returns the number of blocks imported."
  (multiple-value-bind (node-id host tcp-port discovery-port)
      (parse-enode-url enode)
    (declare (ignore discovery-port))
    (multiple-value-bind (status head-number chain-context head-hash)
        (devnet-peer-sync-status node)
      (telemetry-log :info "peer.sync.dialing"
                     :fields (list (cons "enode" enode) (cons "host" host))
                     :sink (devnet-node-telemetry-sink node))
      (multiple-value-bind (peer socket)
          (eth-sync-connect-peer host tcp-port node-id private-key status
                                 :chain-context chain-context
                                 :serve-backend (devnet-peer-serve-backend node)
                                 :snap-backend (devnet-peer-snap-backend node))
          (unwind-protect
               (let ((count
                       (devnet-peer-download-from-resume
                        node peer (node-id-to-hex node-id)
                        head-number head-hash)))
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

(defun devnet-node-claim-sync (node)
  "Claim the right to catch up, or NIL if another session already has it.

ONE SESSION SYNCS AT A TIME. Peers are interchangeable for this purpose -- they
all serve the same canonical chain -- so a second session catching up in
parallel re-downloads and re-executes blocks the first is already importing,
while doubling the contention on the store guard. The claim is taken under the
peer-table mutex because it is the same kind of decision the admission verdicts
are: read a shared fact and act on it in one step."
  (call-with-devnet-peer-table
   node
   (lambda ()
     (unless (devnet-node-syncing-p node)
       (setf (devnet-node-syncing-p node) t)))))

(defun devnet-node-release-sync (node)
  "Give the catch-up claim back. Safe to call without holding it."
  (call-with-devnet-peer-table
   node
   (lambda () (setf (devnet-node-syncing-p node) nil))))

(defun call-with-devnet-sync-claim (node thunk)
  "Run THUNK if no other session is catching up, and always release afterwards.

Returns NIL when the claim was not available, which is not an error: it means
another session is already doing the work."
  (when (devnet-node-claim-sync node)
    (unwind-protect (funcall thunk)
      (devnet-node-release-sync node))))
