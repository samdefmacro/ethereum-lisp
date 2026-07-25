(in-package #:ethereum-lisp.cli)

;;;; Who we are connected to, and whether we will take one more.
;;;;
;;;; This lives in the CLI layer rather than in the networking one because what
;;;; it decides is operator policy — a peer limit set by a flag — not protocol.
;;;; It also keeps the networking layer free of threads: nothing here spawns
;;;; anything, and nothing here reads a clock. NOW is always an argument, so
;;;; every decision this file makes can be checked as a table.
;;;;
;;;; ADMISSION HAPPENS IN TWO PHASES, and the reason is worth stating because it
;;;; is not obvious. A peer's identity comes out of the RLPx handshake, and the
;;;; handshake is a blocking read. Running it on the accept thread would let one
;;;; half-open connection wedge the entire listener, so it has to run on a
;;;; thread of its own — which means the thread must be spawned BEFORE we know
;;;; who is calling. So:
;;;;
;;;;   phase 1, DEVNET-PEER-TABLE-SLOT-VERDICT: identity-free, on the accept
;;;;   thread, bounding how many handshakes may be in flight at once;
;;;;   phase 2, DEVNET-PEER-TABLE-INBOUND-VERDICT: identity-keyed, on the
;;;;   session thread once the handshake has proven who the peer is, where a
;;;;   real disconnect reason can be sent back.
;;;;
;;;; Peers are keyed by the hex node id, the same key the dial registry uses, so
;;;; a peer that dials us while we are dialing it is recognised as one peer.

(defconstant +devnet-default-max-peers+ 25
  "How many peers we hold at once by default. Our policy, not a parity claim.")

(defconstant +devnet-peer-handshake-headroom+ 4
  "How many handshakes beyond the peer limit may be in flight. A handshake can
fail or be refused, so admitting none over the limit would idle the last slots;
the headroom is small because each one costs a thread.")

(defstruct (devnet-peer-entry
            (:constructor make-devnet-peer-entry
                (&key id-hex direction remote-host remote-port socket thread
                      eth-version client-id connected-at)))
  "One connected peer. SOCKET and THREAD are what teardown needs; the rest is
what an operator asks about."
  id-hex
  direction
  remote-host
  remote-port
  socket
  thread
  eth-version
  client-id
  connected-at)

(defstruct (devnet-peer-table
            (:constructor %make-devnet-peer-table (self-id-hex max-peers)))
  "The peers we hold, plus the handshakes not yet resolved into peers.

Not internally locked: the peer manager owns a mutex and takes it around every
call, exactly as the dial registry is guarded. Keeping the lock outside means a
verdict and the change that follows from it are one atomic step."
  self-id-hex
  max-peers
  (pending 0)
  (entries '()))

(defun make-devnet-peer-table (&key self-id-hex (max-peers +devnet-default-max-peers+))
  "A peer table for a node whose own id is SELF-ID-HEX.

MAX-PEERS 0 turns peering off entirely: every verdict refuses."
  (%make-devnet-peer-table self-id-hex (or max-peers 0)))

(defun devnet-peer-table-count (table)
  (length (devnet-peer-table-entries table)))

(defun devnet-peer-table-entry (table id-hex)
  (find id-hex (devnet-peer-table-entries table)
        :key #'devnet-peer-entry-id-hex :test #'equal))

(defun devnet-peer-table-slot-verdict (table)
  "Whether to spawn a session for a connection we have just accepted.

Identity-free by necessity — see the file header. Returns :RESERVE or :NO-SLOT."
  (if (and (plusp (devnet-peer-table-max-peers table))
           (< (+ (devnet-peer-table-count table)
                 (devnet-peer-table-pending table))
              (+ (devnet-peer-table-max-peers table)
                 +devnet-peer-handshake-headroom+)))
      :reserve
      :no-slot))

(defun devnet-peer-table-reserve-slot (table)
  "Count one more handshake in flight."
  (incf (devnet-peer-table-pending table)))

(defun devnet-peer-table-release-slot (table)
  "Give back a reservation whose handshake ended, admitted or not. Never goes
negative: a double release is a bug that must not corrupt the count."
  (setf (devnet-peer-table-pending table)
        (max 0 (1- (devnet-peer-table-pending table)))))

(defun devnet-peer-table-inbound-verdict (table id-hex)
  "Whether to keep a peer whose identity is now known.

Returns :ACCEPT, :SELF, :ALREADY-CONNECTED or :TOO-MANY-PEERS — the refusals map
onto devp2p disconnect reasons, so the peer is told which one it was."
  (cond
    ((and (devnet-peer-table-self-id-hex table)
          (equal id-hex (devnet-peer-table-self-id-hex table)))
     :self)
    ((devnet-peer-table-entry table id-hex) :already-connected)
    ((>= (devnet-peer-table-count table) (devnet-peer-table-max-peers table))
     :too-many-peers)
    (t :accept)))

(defun devnet-peer-table-admit (table entry now)
  "Install ENTRY, stamping when it connected. Returns the entry, or NIL if its
identity was taken while the handshake was still running."
  (let ((id-hex (devnet-peer-entry-id-hex entry)))
    (unless (devnet-peer-table-entry table id-hex)
      (setf (devnet-peer-entry-connected-at entry) now)
      (push entry (devnet-peer-table-entries table))
      entry)))

(defun devnet-peer-table-remove (table id-hex)
  "Forget a peer that has gone. Returns the entry that was removed, or NIL."
  (let ((entry (devnet-peer-table-entry table id-hex)))
    (when entry
      (setf (devnet-peer-table-entries table)
            (remove entry (devnet-peer-table-entries table))))
    entry))

(defun devnet-peer-table-snapshot (table)
  "The connected peers as plists, oldest first — for reporting, never for
mutation."
  (mapcar (lambda (entry)
            (list :id (devnet-peer-entry-id-hex entry)
                  :direction (devnet-peer-entry-direction entry)
                  :remote-host (devnet-peer-entry-remote-host entry)
                  :remote-port (devnet-peer-entry-remote-port entry)
                  :eth-version (devnet-peer-entry-eth-version entry)
                  :client-id (devnet-peer-entry-client-id entry)
                  :connected-at (devnet-peer-entry-connected-at entry)))
          (reverse (devnet-peer-table-entries table))))

;;; What the admin RPC namespace is allowed to see.

(defun devnet-node-admin-backend (node-box)
  "How the admin RPC namespace reaches this node's peering state.

Closures, not the node itself, so the RPC layer goes on knowing nothing about
sockets or listeners. Takes a BOX rather than a node because the RPC service is
built before the node struct exists and needs the backend at construction time;
the box is filled immediately after, and every closure reads it at call time, so
none can capture a half-built node.

Peer reads take the peer-table mutex, never the store guard."
  (flet ((node () (first node-box)))
    (make-admin-backend
     :listening-p
     (lambda () (and (node) (devnet-node-p2p-port (node)) t))
     :peer-count
     (lambda ()
       (if (node)
           (call-with-devnet-peer-table
            (node)
            (lambda ()
              (devnet-peer-table-count (devnet-node-peer-table (node)))))
           0))
     :node-info
     (lambda ()
       (let* ((node (node))
              (port (devnet-node-p2p-port node))
              (host (or (devnet-node-p2p-host node) "0.0.0.0"))
              (head-number (call-with-devnet-node-store-guard
                            node
                            (lambda ()
                              (chain-store-head-number
                               (devnet-node-store node))))))
         (list :enode-id (node-id-to-enode-id-hex
                          (node-id-from-private-key (devnet-node-node-key node)))
               ;; The same name we give peers in our devp2p Hello.
               :client-id +eth-sync-client-id+
               :enode (devnet-node-enode node)
               :ip (eth-sync-socket-endpoint-host host)
               :listener-port (or port 0)
               :listen-address (when port (format nil "~A:~D" host port))
               :eth (list :network-id (devnet-node-network-id node)
                          :genesis (hash32-to-hex
                                    (block-hash
                                     (devnet-node-genesis-block node)))
                          :head (hash32-to-hex
                                 (chain-store-canonical-hash
                                  (devnet-node-store node) head-number))))))
     :peers
     (lambda ()
       (let ((node (node)))
         (mapcar
          (lambda (peer)
            (let* ((id-hex (getf peer :id))
                   (node-id (ignore-errors (node-id-from-hex id-hex)))
                   (host (getf peer :remote-host))
                   (port (or (getf peer :remote-port) 0)))
              (list :enode-id (when node-id (node-id-to-enode-id-hex node-id))
                    :client-id (getf peer :client-id)
                    :enode (when node-id (enode-url node-id host port))
                    :remote-address (format nil "~A:~D" host port)
                    :direction (getf peer :direction)
                    :eth-version (getf peer :eth-version))))
          (call-with-devnet-peer-table
           node
           (lambda ()
             (devnet-peer-table-snapshot (devnet-node-peer-table node)))))))
     ;; admin_addPeer records a static peer for the dialer to pick up rather
     ;; than dialing here: an RPC call must not block on a network round trip.
     ;; Since the outbound dialer is still one-shot per run, a peer added now is
     ;; dialed on the next pass -- say so rather than implying it connects.
     :add-peer
     (lambda (enode)
       (let ((node (node)))
         (call-with-devnet-peer-table
          node
          (lambda ()
            (pushnew enode (devnet-node-peers node) :test #'string=)
            t)))))))
