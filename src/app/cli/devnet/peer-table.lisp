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

(defconstant +devnet-default-inbound-per-ip+ 3)
(defconstant +devnet-default-inbound-per-subnet+ 10)
(defconstant +devnet-peer-ban-score+ -100)

(defstruct (devnet-peer-entry
            (:constructor make-devnet-peer-entry
                (&key id-hex direction remote-host remote-port socket thread
                      eth-version client-id connected-at peer request-queue)))
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
  connected-at
  ;; Process-private handles used by the node-wide sync coordinator. The
  ;; session thread remains the sole reader/writer of PEER's RLPx connection.
  peer
  request-queue)

(defstruct (devnet-peer-table
            (:constructor %make-devnet-peer-table
                (self-id-hex max-peers inbound-per-ip inbound-per-subnet
                 netrestrict)))
  "The peers we hold, plus the handshakes not yet resolved into peers.

Not internally locked: the peer manager owns a mutex and takes it around every
call, exactly as the dial registry is guarded. Keeping the lock outside means a
verdict and the change that follows from it are one atomic step."
  self-id-hex
  max-peers
  inbound-per-ip
  inbound-per-subnet
  netrestrict
  (pending 0)
  (pending-hosts (make-hash-table :test #'equal))
  (scores (make-hash-table :test #'equal))
  (entries '()))

(defun make-devnet-peer-table
    (&key self-id-hex (max-peers +devnet-default-max-peers+)
          (inbound-per-ip +devnet-default-inbound-per-ip+)
          (inbound-per-subnet +devnet-default-inbound-per-subnet+)
          netrestrict)
  "A peer table for a node whose own id is SELF-ID-HEX.

MAX-PEERS 0 turns peering off entirely: every verdict refuses."
  (%make-devnet-peer-table self-id-hex (or max-peers 0)
                           inbound-per-ip inbound-per-subnet netrestrict))

(defun devnet-peer-table-count (table)
  (length (devnet-peer-table-entries table)))

(defun devnet-peer-table-entry (table id-hex)
  (find id-hex (devnet-peer-table-entries table)
        :key #'devnet-peer-entry-id-hex :test #'equal))

(defun devnet-string-parts (string separator)
  (loop with start = 0
        for position = (position separator string :start start)
        collect (subseq string start position)
        while position
        do (setf start (1+ position))))

(defun devnet-ipv4-integer (host)
  (let ((parts (devnet-string-parts host #\.)))
    (when (= (length parts) 4)
      (handler-case
          (let ((octets (mapcar #'parse-integer parts)))
            (when (every (lambda (octet) (<= 0 octet 255)) octets)
              (reduce (lambda (value octet) (+ (ash value 8) octet))
                      octets :initial-value 0)))
        (error () nil)))))

(defun devnet-cidr-matches-p (host cidr)
  "IPv4 CIDR matching plus exact IPv6 hosts. Invalid policy entries fail closed."
  (let ((slash (position #\/ cidr)))
    (if (find #\: host)
        (and (string-equal host (if slash (subseq cidr 0 slash) cidr))
             (or (null slash) (= 128 (parse-integer cidr :start (1+ slash)))))
        (let* ((network-text (if slash (subseq cidr 0 slash) cidr))
               (prefix (if slash (parse-integer cidr :start (1+ slash)) 32))
               (address (devnet-ipv4-integer host))
               (network (devnet-ipv4-integer network-text)))
          (and address network (<= 0 prefix 32)
               (= (ldb (byte prefix (- 32 prefix)) address)
                  (ldb (byte prefix (- 32 prefix)) network)))))))

(defun devnet-peer-host-allowed-p (table host)
  (let ((ranges (devnet-peer-table-netrestrict table)))
    (or (null ranges)
        (some (lambda (range)
                (handler-case (devnet-cidr-matches-p host range)
                  (error () nil)))
              ranges))))

(defun devnet-peer-subnet-key (host)
  (if (find #\: host)
      (format nil "~{~A~^:~}"
              (subseq (devnet-string-parts host #\:) 0
                      (min 4 (length (devnet-string-parts host #\:)))))
      (let ((parts (devnet-string-parts host #\.)))
        (if (= (length parts) 4)
            (format nil "~A.~A.~A" (first parts) (second parts) (third parts))
            host))))

(defun devnet-peer-table-host-count (table host &key subnet-p)
  (let ((key (if subnet-p (devnet-peer-subnet-key host) host)))
    (+ (loop for entry in (devnet-peer-table-entries table)
             when (and (eq :inbound (devnet-peer-entry-direction entry))
                       (equal key
                              (if subnet-p
                                  (devnet-peer-subnet-key
                                   (devnet-peer-entry-remote-host entry))
                                  (devnet-peer-entry-remote-host entry))))
               count entry)
       (loop for pending-host being the hash-keys
               of (devnet-peer-table-pending-hosts table)
             using (hash-value count)
             when (equal key (if subnet-p
                                 (devnet-peer-subnet-key pending-host)
                                 pending-host))
               sum count))))

(defun devnet-peer-table-slot-verdict (table &optional remote-host)
  "Whether to spawn a session for a connection we have just accepted.

Identity-free by necessity — see the file header. Returns :RESERVE or :NO-SLOT."
  (cond
    ((and remote-host (not (devnet-peer-host-allowed-p table remote-host)))
     :netrestrict)
    ((and remote-host
          (>= (devnet-peer-table-host-count table remote-host)
              (devnet-peer-table-inbound-per-ip table)))
     :ip-throttled)
    ((and remote-host
          (>= (devnet-peer-table-host-count table remote-host :subnet-p t)
              (devnet-peer-table-inbound-per-subnet table)))
     :subnet-throttled)
    ((and (plusp (devnet-peer-table-max-peers table))
           (< (+ (devnet-peer-table-count table)
                 (devnet-peer-table-pending table))
              (+ (devnet-peer-table-max-peers table)
                 +devnet-peer-handshake-headroom+)))
     :reserve)
    (t :no-slot)))

(defun devnet-peer-table-reserve-slot (table &optional remote-host)
  "Count one more handshake in flight."
  (incf (devnet-peer-table-pending table))
  (when remote-host
    (incf (gethash remote-host (devnet-peer-table-pending-hosts table) 0))))

(defun devnet-peer-table-release-slot (table &optional remote-host)
  "Give back a reservation whose handshake ended, admitted or not. Never goes
negative: a double release is a bug that must not corrupt the count."
  (setf (devnet-peer-table-pending table)
        (max 0 (1- (devnet-peer-table-pending table))))
  (when remote-host
    (let ((remaining
            (max 0 (1- (gethash remote-host
                                (devnet-peer-table-pending-hosts table) 0)))))
      (if (zerop remaining)
          (remhash remote-host (devnet-peer-table-pending-hosts table))
          (setf (gethash remote-host
                         (devnet-peer-table-pending-hosts table))
                remaining)))))

(defun devnet-peer-score (table id-hex)
  (gethash id-hex (devnet-peer-table-scores table) 0))

(defun devnet-peer-note-score (table id-hex delta)
  (incf (gethash id-hex (devnet-peer-table-scores table) 0) delta))

(defun devnet-peer-table-inbound-verdict (table id-hex)
  "Whether to keep a peer whose identity is now known.

Returns :ACCEPT, :SELF, :ALREADY-CONNECTED or :TOO-MANY-PEERS — the refusals map
onto devp2p disconnect reasons, so the peer is told which one it was."
  (cond
    ((and (devnet-peer-table-self-id-hex table)
          (equal id-hex (devnet-peer-table-self-id-hex table)))
     :self)
    ((devnet-peer-table-entry table id-hex) :already-connected)
    ((<= (devnet-peer-score table id-hex) +devnet-peer-ban-score+)
     :useless-peer)
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

(defun devnet-peer-table-count-by-direction (table direction)
  "How many peers we hold in one direction. This is the ONLY authority on the
outbound peer count; the dial registry's :CONNECTED marker is not a counter."
  (count direction (devnet-peer-table-entries table)
         :key #'devnet-peer-entry-direction))

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
              (host (devnet-node-advertised-host node))
              (genesis-hash (block-hash (devnet-node-genesis-block node))))
         ;; HTTP and WebSocket dispatch already run the complete request under
         ;; NODE's store guard.  Acquiring that non-recursive mutex again here
         ;; makes the production admin_nodeInfo path fail with -32603 on SBCL.
         (let* ((store (devnet-node-store node))
                (number (chain-store-head-number store))
                (head-hash
                  (or (chain-store-canonical-hash store number)
                      ;; An empty restored/snap store can expose its initial
                      ;; head number before the canonical-number index exists.
                      ;; At zero, the configured genesis is the only honest
                      ;; head.  At any other height, report JSON null rather
                      ;; than inventing a hash.
                      (and (zerop number) genesis-hash))))
         (list :enode-id (node-id-to-enode-id-hex
                          (node-id-from-private-key (devnet-node-node-key node)))
               ;; The same name we give peers in our devp2p Hello.
               :client-id +eth-sync-client-id+
               :enode (devnet-node-enode node)
               :ip host
               :listener-port (or port 0)
               :listen-address (when port (format nil "~A:~D" host port))
               :eth (list :network-id (devnet-node-network-id node)
                          :genesis (hash32-to-hex genesis-hash)
                          :head (and head-hash
                                     (hash32-to-hex head-hash)))))))
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
            t))))
     :remove-peer
     (lambda (enode)
       (let* ((node (node))
              (id-hex
                (node-id-to-hex
                 (nth-value 0 (parse-enode-url enode))))
              (removed-static-p nil)
              (entry
                (call-with-devnet-peer-table
                 node
                 (lambda ()
                   (setf removed-static-p
                         (not (null
                               (member enode (devnet-node-peers node)
                                       :test #'string=))))
                   (setf (devnet-node-peers node)
                         (remove enode (devnet-node-peers node)
                                 :test #'string=))
                   (devnet-peer-table-remove
                    (devnet-node-peer-table node) id-hex)))))
         #+sbcl
         (when (and entry (devnet-peer-entry-socket entry))
           (ignore-errors
             (sb-bsd-sockets:socket-close
              (devnet-peer-entry-socket entry))))
         (if (or entry removed-static-p) t nil))))))
