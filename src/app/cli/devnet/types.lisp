(in-package #:ethereum-lisp.cli)

(defstruct (devnet-endpoint-config
            (:constructor %make-devnet-endpoint-config
                (&key host port rpc-prefix cors-origins allowed-hosts
                      allowed-method-p)))
  host
  port
  rpc-prefix
  cors-origins
  allowed-hosts
  allowed-method-p)

(defun make-devnet-endpoint-config
    (&key host port rpc-prefix cors-origins allowed-hosts allowed-method-p)
  (%make-devnet-endpoint-config
   :host host
   :port port
   :rpc-prefix rpc-prefix
   :cors-origins (and cors-origins (copy-list cors-origins))
   :allowed-hosts (and allowed-hosts (copy-list allowed-hosts))
   :allowed-method-p allowed-method-p))

(defstruct (devnet-txpool-policy
            (:constructor %make-devnet-txpool-policy
                (&key allow-unprotected-transactions-p price-limit
                      price-bump-percent account-slot-limit global-slot-limit
                      account-queue-limit global-queue-limit local-addresses
                      no-local-exemptions-p lifetime-seconds)))
  allow-unprotected-transactions-p
  price-limit
  price-bump-percent
  account-slot-limit
  global-slot-limit
  account-queue-limit
  global-queue-limit
  local-addresses
  no-local-exemptions-p
  lifetime-seconds)

(defun make-devnet-txpool-policy
    (&key allow-unprotected-transactions-p price-limit price-bump-percent
          account-slot-limit global-slot-limit account-queue-limit
          global-queue-limit local-addresses no-local-exemptions-p
          lifetime-seconds)
  (%make-devnet-txpool-policy
   :allow-unprotected-transactions-p allow-unprotected-transactions-p
   ;; Keep the operator defaults aligned with the admission-service defaults.
   ;; NIL means the flag was omitted; zero remains an explicit operator value.
   :price-limit (if (null price-limit) 1 price-limit)
   :price-bump-percent
   (if (null price-bump-percent) 10 price-bump-percent)
   :account-slot-limit
   (if (null account-slot-limit) 16 account-slot-limit)
   :global-slot-limit
   (if (null global-slot-limit) 5120 global-slot-limit)
   :account-queue-limit
   (if (null account-queue-limit) 64 account-queue-limit)
   :global-queue-limit
   (if (null global-queue-limit) 1024 global-queue-limit)
   :local-addresses (and local-addresses (copy-list local-addresses))
   :no-local-exemptions-p no-local-exemptions-p
   :lifetime-seconds
   (if (null lifetime-seconds) (* 3 60 60) lifetime-seconds)))

(defstruct (devnet-persistence-state
            (:constructor make-devnet-persistence-state
                (&key (current-generation 0) (chain-generation 0)
                      chain-id genesis-hash authority-id)))
  (current-generation 0 :type integer)
  (chain-generation 0 :type integer)
  chain-id
  genesis-hash
  authority-id)

(defstruct (devnet-coalesced-notification
            (:constructor make-devnet-coalesced-notification ()))
  "One coalesced wakeup for a node-wide background worker.

The producer and consumer are different threads. PENDING-P is deliberately a
single bit rather than a queue: any number of notifications received during one
worker pass require at most one follow-up pass, so traffic cannot allocate
unbounded wakeup work."
  (lock #+sbcl
        (sb-thread:make-mutex :name "ethereum-lisp-worker-notification")
        #-sbcl nil)
  (changed #+sbcl
           (sb-thread:make-waitqueue :name "ethereum-lisp-worker-notification")
           #-sbcl nil)
  pending-p)

(defstruct (devnet-snap-qos
            (:constructor make-devnet-snap-qos ()))
  "Node-wide SNAP message-rate trackers used for geth-style scheduling.

Each live peer request queue contributes one shared RTT and one throughput EWMA
per response type.  ROUND-TRIP and CONFIDENCE cache the periodically tuned pool
estimate: new connections detune confidence, while successful tuning converges
it back toward one.  Keeping this at node scope lets a replacement peer inherit
the established pool instead of relearning it from the cold minimum."
  (lock #+sbcl
        (sb-thread:make-mutex :name "ethereum-lisp-snap-qos")
        #-sbcl nil)
  (round-trips (make-hash-table :test #'eq))
  ;; Queue -> response-id/units-per-second table. The nested tables are
  ;; snapshots, so pool means never acquire a peer queue lock while holding the
  ;; QoS lock.
  (throughputs (make-hash-table :test #'eq))
  (round-trip 20d0)
  (confidence 1d0)
  (tuned-at (get-internal-real-time)))

(defconstant +devnet-blob-cell-cache-limit+ 32
  "How many blobs' EIP-7594 derivations a node keeps. Our policy: one entry is
the 128 KiB blob key, 256 KiB of cells and 6 KiB of proofs, so the cache stays
near 12 MiB -- above the largest scheduled blob count per block (bpo2, 21).")

(defstruct (devnet-blob-cell-cache
            (:constructor make-devnet-blob-cell-cache ()))
  "Cells and cell proofs per blob, keyed by the blob's bytes.

Pinned geth's blobpool computes a transaction's cells once, when it enters the
pool, and serves eth/72 GetCells and pooled wrappers from what it stored. We
derive lazily instead, on the first eth/72 request, but at most once per blob,
and callers do it outside the store guard."
  (lock #+sbcl (sb-thread:make-mutex :name "ethereum-lisp-blob-cell-cache")
        #-sbcl nil)
  (entries (make-hash-table :test #'equalp))
  (order '()))

(defun devnet-blob-cell-cache-derivation (cache blob function)
  "Return (VALUES CELLS PROOFS) for BLOB, computing them with FUNCTION once.

FUNCTION takes the blob and returns cells and proofs as two values. It runs
outside the cache lock; two threads racing on a new blob may both compute it,
which costs time but never a wrong answer, since the derivation is a pure
function of the blob. Keys are the blob bytes themselves: an equalp table
compares them in full, so a colliding hash costs a comparison, never a wrong
entry."
  (let ((key (copy-seq (ensure-byte-vector blob))))
    (flet ((locked (thunk)
             #+sbcl
             (sb-thread:with-mutex ((devnet-blob-cell-cache-lock cache))
               (funcall thunk))
             #-sbcl
             (funcall thunk)))
      (let ((cached
              (locked
               (lambda ()
                 (gethash key (devnet-blob-cell-cache-entries cache))))))
        (if cached
            (values (car cached) (cdr cached))
            (multiple-value-bind (cells proofs) (funcall function blob)
              (locked
               (lambda ()
                 (let ((entries (devnet-blob-cell-cache-entries cache)))
                   (unless (gethash key entries)
                     (setf (gethash key entries) (cons cells proofs))
                     (push key (devnet-blob-cell-cache-order cache))
                     (when (> (hash-table-count entries)
                              +devnet-blob-cell-cache-limit+)
                       (let ((oldest
                               (car (last
                                     (devnet-blob-cell-cache-order cache)))))
                         (setf (devnet-blob-cell-cache-order cache)
                               (butlast (devnet-blob-cell-cache-order cache)))
                         (remhash oldest entries)))))))
              (values cells proofs)))))))

(defstruct (devnet-node
            (:constructor %make-devnet-node
                (&key genesis-path store config genesis-block service
                      public-service telemetry-sink jwt-secret-path log-path
                      database-path (db-engine :file) pid-file-path network-id
                      public-api-modules engine-endpoint-config
                      public-endpoint-config txpool-policy
                      dev-mode-p coinbase store-guard-function
                      store-guard-try-function
                      store-guard-priority-pending-function
                      store-guard-ledger
                      persistence-state
                      candidate-persistence-function
                      peer-sync-progress-function
                      peer-sync-progress-reset-function
                      canonical-transition-persistence-function
                      txpool-journal-path
                      txpool-rejournal-seconds
                      dev-period-seconds
                      miner-gas-limit
                      peers
                      bootnodes
                      node-key
                      discovery-enabled-p
                      discovery-dns
                      discovery-dns-sequence
                      discovery-dns-sequence-persistence-function
                      enr-seq
                      enr-seq-persistence-function
                      dial-registry
                      dial-guard-function
                      p2p-host
                      p2p-port
                      nat-policy
                      peer-table
                      discovery-table
                      metrics-host
                      metrics-port
                      ws-enabled-p
                      ws-host
                      ws-port
                      ws-origins
                      ws-rpc-prefix
                      ws-allowed-method-p)))
  genesis-path
  store
  config
  genesis-block
  service
  public-service
  telemetry-sink
  jwt-secret-path
  log-path
  database-path
  (db-engine :file)
  pid-file-path
  network-id
  public-api-modules
  engine-endpoint-config
  public-endpoint-config
  txpool-policy
  dev-mode-p
  coinbase
  store-guard-function
  ;; The same guard, but giving up rather than waiting. See
  ;; CALL-WITH-DEVNET-NODE-STORE-GUARD-IF-FREE.
  store-guard-try-function
  ;; A function of no arguments, true while an Engine request is waiting for
  ;; the store guard.  Long guard holders (the forward batch importer) poll it
  ;; to end their hold early and step aside.  NIL means no priority waiter can
  ;; exist.  See MAKE-DEVNET-STORE-GUARD-FUNCTION.
  store-guard-priority-pending-function
  ;; The DEVNET-STORE-GUARD-LEDGER of the store guard, read without the guard by
  ;; the health and metrics endpoints (current hold age, last Engine request).
  ;; NIL for a node built without one.
  store-guard-ledger
  persistence-state
  ;; One durable candidate sink is shared by Engine and P2P imports.  The P2P
  ;; path may additionally supply a peer-sync progress record that the adapter
  ;; commits in the candidate's database batch.
  candidate-persistence-function
  ;; Point reader for a peer's last durable contiguous candidate.  Keeping the
  ;; database adapter behind a closure avoids leaking persistence concerns into
  ;; the networking package.
  peer-sync-progress-function
  ;; Atomically removes a cursor whose branch Engine forkchoice abandoned.
  ;; Its replacement is written with the first candidate on the new branch.
  peer-sync-progress-reset-function
  canonical-transition-persistence-function
  txpool-journal-path
  txpool-rejournal-seconds
  dev-period-seconds
  miner-gas-limit
  peers
  bootnodes
  node-key
  (discovery-enabled-p t)
  discovery-dns
  discovery-dns-sequence
  discovery-dns-sequence-persistence-function
  enr-seq-persistence-function
  dial-registry
  dial-guard-function
  ;; Inbound peering. P2P-PORT NIL means no listener at all, which is the
  ;; default: binding a fixed port by habit is how two nodes on one machine
  ;; collide. The peer table carries the peer limit and our own identity.
  p2p-host
  p2p-port
  nat-policy
  peer-table
  (snap-qos (make-devnet-snap-qos))
  ;; Who discovery knows about, bucketed by distance. Guarded by the same mutex
  ;; as the peer table and the dial registry.
  discovery-table
  ;; Where --metrics.addr/--metrics.port asked the metrics endpoint to bind.
  ;; A port with --metrics off binds nothing; see DEVNET-NODE-METRICS-ENDPOINT.
  metrics-host
  metrics-port
  ;; The WebSocket endpoint. Off unless --ws; it serves the public surface under
  ;; its own --ws.api filter (WS-ALLOWED-METHOD-P) plus eth_subscribe, which
  ;; only means anything on a connection that stays open.
  ws-enabled-p
  ws-host
  ws-port
  ws-origins
  ws-rpc-prefix
  ws-allowed-method-p
  ;; Whether a peer session is currently catching up. Guarded by the peer-table
  ;; mutex, and the reason it exists is in DEVNET-NODE-CLAIM-SYNC.
  (syncing-p nil)
  ;; One process-local chance to resume a matching durable Snap session before
  ;; the ordinary stale-pivot policy may rebase it.  The session's exact healer
  ;; checkpoint is optional: range cursors and completed-subtree proofs are
  ;; already expensive reusable work, and a routine process restart must not
  ;; replace their pivot before a live source gets one real attempt.  The chance
  ;; is consumed only when that attempt starts, so waiting for peers is free.
  (snap-session-resume-p t)
  ;; A durable state session stays pinned even after the CL head crosses the
  ;; ordinary pivot-age window. Only the healer's bounded liveness policy may
  ;; authorize replacing productive work. This latch is cleared after the
  ;; requested atomic session rebase commits.
  (snap-session-rebase-p nil)
  ;; The exact FCU-authorized successor observed with the bounded stale-pivot
  ;; decision.  The Engine implementation may consume its transient
  ;; forkchoice queue before the coordinator's next pass; retaining this hash
  ;; prevents a true stale decision from degrading into an unauthorized
  ;; peer-head catch-up or an idle large-gap loop.  It is process-local and is
  ;; cleared only after the durable rebase commits.
  (snap-session-rebase-target nil)
  ;; SNAP peers which explicitly rejected the active pivot's state are an
  ;; availability fact for that pivot, not a score penalty. Keep their stable
  ;; node ids process-locally across finite coordinator passes so the same live
  ;; sessions are not probed and fanned out again every second. A genuinely new
  ;; pivot clears the set; restart also deliberately gives peers a fresh chance.
  snap-unavailable-pivot-hash
  (snap-unavailable-peer-ids (make-hash-table :test #'equal))
  ;; The last useful bounded TrieNodes response window for the active pivot.
  ;; Keep this beside the rejection set so a finite coordinator retry cannot
  ;; forget that the supposedly exhausted generation was serving efficiently
  ;; only seconds earlier. A genuinely new pivot clears both observations.
  snap-heal-last-efficient-response-at
  ;; Dependency workers can discover pruning concurrently with coordinator
  ;; callbacks. This lock protects only the process-local fields above and
  ;; is never held across peer, store, or source-pool I/O.
  (snap-unavailable-peer-lock
    #+sbcl (sb-thread:make-mutex
            :name "ethereum-lisp-snap-unavailable-peers")
    #-sbcl nil)
  ;; A bounded condition-variable notification from peer session threads to the
  ;; node-wide coordinator.  It is independent of both the peer-table mutex and
  ;; the store guard, so an announcement can never enter either lock order.
  (sync-notification (make-devnet-coalesced-notification))
  ;; Engine FCU publishes an open payload while holding the store guard, then
  ;; signals this independent condition. The builder wakes, acquires the guard
  ;; after FCU returns, and spends the proposer's wait improving the payload.
  (payload-improvement-notification (make-devnet-coalesced-notification))
  ;; The last eth chain context discovery managed to read, kept so discovery
  ;; never has to WAIT for the store guard to learn our fork id. See
  ;; DEVNET-NODE-CHAIN-CONTEXT for why waiting there is not an option.
  (chain-context-cache nil)
  ;; What eth_syncing needs from the guarded store, as one immutable plist
  ;; (:CURRENT head-number :HIGHEST in-memory-target :TARGETS-P bool) replaced
  ;; wholesale at every store-guard release. Readers take it without any lock;
  ;; see DEVNET-NODE-PUBLISH-SYNC-VIEW. NIL until the first publication.
  (sync-view nil)
  ;; What an inbound eth Status needs from the guarded store, as one immutable
  ;; plist (:HEAD-NUMBER :HEAD-TIMESTAMP :GENESIS-HASH :BEST-HASH) replaced
  ;; wholesale at every store-guard release, so accepting a peer never waits
  ;; for the guard; see DEVNET-NODE-PUBLISH-STATUS-VIEW. NIL until the first
  ;; publication.
  (status-view nil)
  ;; The public read view (NODE-STORE-PUBLISH-READ-VIEW): the recent canonical
  ;; chain as immutable data, republished at every store-guard release so the
  ;; public RPC can answer block, receipt and head reads without waiting for
  ;; the guard. NIL until the first publication; readers then use the guard.
  (read-view nil)
  ;; EIP-7594 cells and cell proofs derived for pooled blobs, served to eth/72
  ;; peers without recomputing (DEVNET-BLOB-CELL-CACHE-DERIVATION). Bounded;
  ;; has its own lock and is never touched under the store guard.
  (blob-cell-cache (make-devnet-blob-cell-cache))
  ;; EIP-778 sequence and the exact pairs it describes. The responder updates
  ;; these under the peer-table lock, so a changed endpoint/fork id increments
  ;; monotonically even across a chain reorg whose head number decreases.
  (enr-seq 1)
  (enr-pairs nil))

(defun devnet-make-mutex (name)
  "A mutex on SBCL, NIL elsewhere. CALL-WITH-DEVNET-MUTEX degrades accordingly."
  #+sbcl (sb-thread:make-mutex :name name)
  #-sbcl (progn name nil))

(defun call-with-devnet-mutex (mutex thunk)
  #+sbcl
  (if mutex
      (sb-thread:with-mutex (mutex) (funcall thunk))
      (funcall thunk))
  #-sbcl
  (progn mutex (funcall thunk)))

(defun call-with-devnet-store-guard-release-hook (release-hook thunk)
  "Call THUNK, then RELEASE-HOOK while the caller still owns the guard.

The hook runs however THUNK exits: after a normal return the store holds what
THUNK committed, and after a non-local exit CHAIN-STORE-ATOMIC-COMMIT has
already rolled THUNK's transaction back, so either way the hook sees committed
state. A failing hook must never turn a successful guarded operation into an
error, so its conditions are dropped here."
  (if release-hook
      (unwind-protect (funcall thunk)
        (handler-case (funcall release-hook)
          (serious-condition () nil)))
      (funcall thunk)))

(defparameter *devnet-store-guard-priority-yield-seconds* 2
  "How long a guard taker that is not an Engine request defers to one.

Our policy. Waiting ends as soon as every waiter owns the guard in turn; the
bound only keeps a continuous stream of Engine requests from starving the
importer and the other background holders completely.")

(defparameter *devnet-engine-guard-busy-seconds* 7
  "How long an Engine request waits behind background store-guard holds before
it gives up. NIL waits without bound, as every Engine request did at b5161312.

Our policy, derived from the consensus client's own deadline: the execution-
apis Engine timeouts (engine/common.md) are 8 s for engine_newPayload and
engine_forkchoiceUpdated and 1 s for the metadata calls, and a CL abandons the
request after them. Seven seconds lets a normal one-block hold finish (a Hoodi
block cost about 6 s at b5161312) and leaves about a second for the read,
dispatch and the reply, so a request that gives up still answers before the
CL's 8 s deadline. Only time spent behind a background holder (an importer, a
peer being served) counts; waiting behind another Engine request is the CL's
own serialization, which go-ethereum also imposes (newPayloadLock and
forkchoiceLock in eth/catalyst/api.go), and it is not bounded here.

A newPayload or forkchoiceUpdated that gives up answers SYNCING through
ETHEREUM-LISP.RPC:RPC-REQUEST-GUARD-BUSY, as go-ethereum's delayPayloadImport
does while its downloader owns the chain; any other guarded Engine method
answers a JSON-RPC error instead of holding a worker slot to the 30 s HTTP
deadline.")

(defparameter *devnet-engine-guard-free-methods*
  '("eth_syncing" "engine_getBlobsV3"
    "engine_exchangeCapabilities" "engine_getClientVersionV1")
  "Engine-endpoint methods served without the store guard.

eth_syncing answers from the view published at the last guard release, and
engine_getBlobsV3 from its own snapshot (both non-blocking by design). The
two metadata calls read no store state at all: exchangeCapabilities answers
the static capability list and getClientVersionV1 the static client version.
The CL gives both a 1 s deadline and treats a miss as the EL being offline; on
Hoodi (b5161312) Lighthouse logged an exchangeCapabilities timeout every
second while a peer session held the guard. go-ethereum takes no chain lock for
either (eth/catalyst/api.go ExchangeCapabilities, GetClientVersionV1).")

;;; Guard-hold attribution.
;;;
;;; An Engine request that waited for the store guard cannot tell from its own
;;; clock WHO it waited for, and on Hoodi (aee866f7) newPayload and
;;; forkchoiceUpdated answers took 5-25 s with no execution at all. The ledger
;;; records every hold as it is released -- the holder's activity label, how
;;; long it held the guard and how much of that was the release hook -- so a
;;; waiter can name the holds that ended while it waited, and a hold longer
;;; than a bound can be logged by itself.

(defconstant +devnet-store-guard-ledger-size+ 32
  "How many released holds the ledger keeps. A waiter names only holds that
ended during its wait, so this bounds the length of that list, not its age.")

(defstruct (devnet-store-guard-ledger
            (:constructor make-devnet-store-guard-ledger ()))
  "Released store-guard holds, newest last. Written only by the guard owner,
just before it releases; read by the next owner, so the mutex orders every
access. HOLDER-LABEL is the current owner's label, set on acquisition; a waiter
reads it racily, only to name who it found holding the guard. So are
HOLDER-STARTED-AT (the internal real time the current owner acquired the
guard, NIL while it is free), HOLDER-ENGINE-P (true when the owner is an Engine
request) and HOLDER-DETAIL (the DEVNET-STORE-GUARD-BLOCK-NOTE the owner is
filling in). LAST-PRIORITY-AT is the time the most recent Engine request asked
for the guard. All are written by the thread that owns (or asks for) the guard
and read racily, without the guard, by the health and metrics endpoints and by
a waiter naming the hold in progress: a scrape must answer while a long import
holds the store, and a value one hold stale is still a correct observation. A
racy reader must therefore tolerate a label with a NIL start time."
  (holder-label nil)
  (holder-started-at nil)
  (last-priority-at nil)
  (holder-engine-p nil)
  (holder-detail nil)
  (holds (make-array +devnet-store-guard-ledger-size+ :initial-element nil)
   :type simple-vector)
  (next 0 :type fixnum))

(defstruct (devnet-store-guard-hold
            (:constructor make-devnet-store-guard-hold
                (label started-at ended-at hook-ms &optional detail)))
  "One released hold. STARTED-AT and ENDED-AT are internal real times. DETAIL
is the hold's DEVNET-STORE-GUARD-BLOCK-NOTE description, or NIL."
  (label nil :read-only t)
  (started-at 0 :read-only t)
  (ended-at 0 :read-only t)
  (hook-ms 0 :read-only t)
  (detail nil :read-only t))

;;; What a hold was doing.
;;;
;;; The label names the activity (sync-gap-fill, forward-batch-import,
;;; snap-serve-account-range ...). An importer additionally notes each block it
;;; imports under the hold, so a long hold says which blocks it cost and a run
;;; can tell slow execution (one block, many seconds) from a hold that spans
;;; many blocks. The detail is filled in by the holder only, while it owns the
;;; mutex; a waiter reads it racily, to name what it is waiting behind.

(defstruct (devnet-store-guard-block-note
            (:constructor make-devnet-store-guard-block-note ()))
  (first-block nil)
  (last-block nil)
  (block-count 0 :type fixnum))

(defvar *devnet-store-guard-block-note* nil
  "The DEVNET-STORE-GUARD-BLOCK-NOTE of the hold the current thread owns, or
NIL outside a hold.")

(defun devnet-store-guard-note-block (number)
  "Record that the current store-guard hold imports block NUMBER. Does nothing
outside a hold."
  (let ((detail *devnet-store-guard-block-note*))
    (when (and detail (integerp number))
      (unless (devnet-store-guard-block-note-first-block detail)
        (setf (devnet-store-guard-block-note-first-block detail) number))
      (setf (devnet-store-guard-block-note-last-block detail) number)
      (incf (devnet-store-guard-block-note-block-count detail))))
  number)

(defun devnet-store-guard-block-note-description (detail)
  "N for one block, FIRST..LAST(COUNT) for several, NIL for none."
  (when detail
    (let ((first (devnet-store-guard-block-note-first-block detail))
          (last (devnet-store-guard-block-note-last-block detail))
          (count (devnet-store-guard-block-note-block-count detail)))
      (cond ((or (null first) (zerop count)) nil)
            ((= count 1) (format nil "~D" first))
            (t (format nil "~D..~D(~D)" first last count))))))

(defun devnet-internal-time-ms (ticks)
  (round (* 1000 ticks) internal-time-units-per-second))

(defun devnet-store-guard-hold-ms (hold)
  (devnet-internal-time-ms
   (- (devnet-store-guard-hold-ended-at hold)
      (devnet-store-guard-hold-started-at hold))))

(defun devnet-store-guard-ledger-record (ledger hold)
  (let ((next (devnet-store-guard-ledger-next ledger))
        (holds (devnet-store-guard-ledger-holds ledger)))
    (setf (svref holds next) hold
          (devnet-store-guard-ledger-next ledger)
          (mod (1+ next) (length holds)))
    hold))

(defun devnet-store-guard-ledger-holds-ended-after (ledger since)
  "The recorded holds that ended after internal time SINCE, oldest first. Call
it while owning the guard. Strictly after: the clock is coarse (a millisecond
on SBCL), and a hold released in the tick a wait began usually ended before it."
  (let* ((holds (devnet-store-guard-ledger-holds ledger))
         (size (length holds))
         (next (devnet-store-guard-ledger-next ledger)))
    (loop for offset from 0 below size
          for hold = (svref holds (mod (+ next offset) size))
          when (and hold (> (devnet-store-guard-hold-ended-at hold) since))
            collect hold)))

(defun devnet-store-guard-hold-description (hold)
  "LABEL:HOLDms, with +HOOKms when the release hook took any measurable time
and [blocks=DETAIL] when the hold noted blocks. HOLDms includes the hook."
  (let ((hook-ms (devnet-store-guard-hold-hook-ms hold))
        (detail (devnet-store-guard-hold-detail hold)))
    (format nil "~A:~D~:[~*~;+~D~]~@[[blocks=~A]~]"
            (devnet-store-guard-hold-label hold)
            (devnet-store-guard-hold-ms hold)
            (plusp hook-ms) hook-ms
            detail)))

(defun devnet-store-guard-current-hold-description (ledger)
  "LABEL:HELDms(holding)[blocks=DETAIL] for the hold in progress, read racily,
or NIL when the guard looks free."
  (let ((label (devnet-store-guard-ledger-holder-label ledger))
        (started-at (devnet-store-guard-ledger-holder-started-at ledger))
        (detail (devnet-store-guard-block-note-description
                 (devnet-store-guard-ledger-holder-detail ledger))))
    (when (and label started-at)
      (format nil "~A:~D(holding)~@[[blocks=~A]~]"
              label
              (devnet-internal-time-ms (- (get-internal-real-time) started-at))
              detail))))

(defparameter *devnet-store-guard-long-hold-ms* 1000
  "Holds at least this long are reported to the guard's LONG-HOLD-FUNCTION.
Our policy: the forward importer and the payload builder bound their holds to
one second, so anything longer is worth a log line.")

(defun call-with-devnet-store-guard-hold
    (ledger release-hook long-hold-function thunk &key engine-p)
  "Call THUNK as the owner of the guard LEDGER describes, then its release hook,
recording the hold. The caller owns the mutex for the whole call.

RELEASE-HOOK keeps CALL-WITH-DEVNET-STORE-GUARD-RELEASE-HOOK's contract. A
hold of *DEVNET-STORE-GUARD-LONG-HOLD-MS* or more is passed to
LONG-HOLD-FUNCTION, whose conditions are dropped like the hook's. ENGINE-P
marks the owner as an Engine request, so a waiting Engine request can tell the
CL's own serialization from a background hold. THUNK may note the blocks it
imports through DEVNET-STORE-GUARD-NOTE-BLOCK; the note travels with the hold."
  (let ((started-at (get-internal-real-time))
        (label (ethereum-lisp.telemetry:telemetry-activity-label))
        (detail (make-devnet-store-guard-block-note)))
    ;; Start time, owner kind and note before the label: a racy reader that
    ;; sees the label also sees a start time no older than this hold's.
    (setf (devnet-store-guard-ledger-holder-started-at ledger) started-at
          (devnet-store-guard-ledger-holder-engine-p ledger) engine-p
          (devnet-store-guard-ledger-holder-detail ledger) detail)
    #+sbcl (sb-thread:barrier (:write))
    (setf (devnet-store-guard-ledger-holder-label ledger) label)
    (let ((hook-started-at nil))
      (unwind-protect
           (let ((*devnet-store-guard-block-note* detail))
             (call-with-devnet-store-guard-release-hook
              (and release-hook
                   (lambda ()
                     (setf hook-started-at (get-internal-real-time))
                     (funcall release-hook)))
              thunk))
        (let* ((ended-at (get-internal-real-time))
               (hold (make-devnet-store-guard-hold
                      label started-at ended-at
                      (if hook-started-at
                          (devnet-internal-time-ms (- ended-at hook-started-at))
                          0)
                      (devnet-store-guard-block-note-description detail))))
          (devnet-store-guard-ledger-record ledger hold)
          (setf (devnet-store-guard-ledger-holder-label ledger) nil
                (devnet-store-guard-ledger-holder-started-at ledger) nil
                (devnet-store-guard-ledger-holder-engine-p ledger) nil
                (devnet-store-guard-ledger-holder-detail ledger) nil)
          (when (and long-hold-function
                     (>= (devnet-store-guard-hold-ms hold)
                         *devnet-store-guard-long-hold-ms*))
            (handler-case (funcall long-hold-function hold)
              (serious-condition () nil))))))))

(defun devnet-store-guard-note-priority-wait
    (ledger wait-started-at found-label &key holding)
  "Account a priority waiter's wait that just ended in owning the guard, or in
giving up.

Adds guardWaitMs and guardWaitedFor to the current request's wait accounting
(TELEMETRY-NOTE-WAIT): the holds that ended while it waited, or, when the
ledger lost them, the label it found holding the guard. HOLDING, from a waiter
that gave up, describes the hold still in progress and is named last. A waiter
that gave up does not own the mutex, so it reads the ledger racily; each slot
is replaced whole, so at worst it misses a hold that ended at that moment."
  (let ((waited-ticks (- (get-internal-real-time) wait-started-at)))
    (when (plusp waited-ticks)
      (let* ((holds (devnet-store-guard-ledger-holds-ended-after
                     ledger wait-started-at))
             (names (append (mapcar #'devnet-store-guard-hold-description holds)
                            (and holding (list holding)))))
        (ethereum-lisp.telemetry:telemetry-note-wait
         "guard"
         (floor (* 1000000 waited-ticks) internal-time-units-per-second)
         (cond
           (names (format nil "~{~A~^ ~}" names))
           (found-label (format nil "~A:?" found-label))))))))

(defparameter *devnet-store-guard-busy-check-seconds* 0.1
  "How often a bounded Engine wait looks at who holds the guard. The mutex is
handed over as soon as it is released; this only sets how finely background
waiting time is measured.")

#+sbcl
(defun devnet-store-guard-bounded-priority-wait
    (mutex ledger budget wait-started-at found-label owned-function)
  "Take MUTEX for an Engine request and call OWNED-FUNCTION, unless background
holds keep it out for BUDGET seconds.

Time spent while the owner is another Engine request (HOLDER-ENGINE-P) does
not count against BUDGET. When the budget runs out the wait is accounted like
any other (guardWaitMs, guardWaitedFor, ending with the hold still in
progress) and ETHEREUM-LISP.RPC:RPC-REQUEST-GUARD-BUSY is signalled; the
caller's unwind drops the request out of the priority count."
  (let ((background-ticks 0)
        (budget-ticks (* budget internal-time-units-per-second))
        (checked-at (get-internal-real-time)))
    (loop
      (let ((ran-p nil)
            (results nil))
        (sb-thread:with-mutex (mutex :timeout *devnet-store-guard-busy-check-seconds*)
          (setf ran-p t
                results (multiple-value-list (funcall owned-function))))
        (when ran-p
          (return (values-list results)))
        (let ((now (get-internal-real-time)))
          (unless (devnet-store-guard-ledger-holder-engine-p ledger)
            (incf background-ticks (- now checked-at)))
          (setf checked-at now)
          (when (>= background-ticks budget-ticks)
            (let ((holding (devnet-store-guard-current-hold-description ledger)))
              (devnet-store-guard-note-priority-wait
               ledger wait-started-at found-label :holding holding)
              (error 'ethereum-lisp.rpc:rpc-request-guard-busy
                     :holder holding
                     :waited-ms (devnet-internal-time-ms
                                 (- now wait-started-at))))))))))

(defun make-devnet-store-guard-function
    (&key release-hook long-hold-function)
  "Return (VALUES GUARD TRY PRIORITY-GUARD PRIORITY-PENDING-P LEDGER) over one
mutex.

GUARD blocks until the mutex is free; TRY gives up instead of waiting. Two
functions rather than one with a flag so that a caller cannot accidentally
block by omitting an argument.

PRIORITY-GUARD is GUARD for Engine API requests: while it waits, the
no-argument PRIORITY-PENDING-P returns true, which is the signal a long holder
such as the forward batch importer uses to commit what it has, release the
mutex, and stay off it until the waiter got in. The count drops as soon as the
waiter owns the mutex, not when it finishes, so a holder that stepped aside
never spins through the Engine request's own work. SBCL mutexes are not fair;
without this signal a holder that re-acquires in a loop can keep a waiting
Engine request out indefinitely. A priority waiter that had to wait reports
guardWaitMs and guardWaitedFor through TELEMETRY-NOTE-WAIT, so the Engine
request log names the holds it waited behind. GUARD and TRY defer to a waiting
Engine request (up to *DEVNET-STORE-GUARD-PRIORITY-YIELD-SECONDS*; TRY simply
fails), because a holder that releases and re-takes the mutex otherwise wins
against the woken waiter.

RELEASE-HOOK, when given, is a function of no arguments that all three run
just before they release the mutex, still owning it. It is how state that only
the guard may read gets published for readers that must never wait for the
guard (eth_syncing): the guard is almost always held on a busy node, but it is
released between holds, and that boundary is the one place where the store is
both readable and committed. It must be cheap; it runs on every release.

LONG-HOLD-FUNCTION, when given, receives each DEVNET-STORE-GUARD-HOLD of at
least *DEVNET-STORE-GUARD-LONG-HOLD-MS*, still under the mutex. LEDGER is the
DEVNET-STORE-GUARD-LEDGER all holds are recorded in."
  (let ((ledger (make-devnet-store-guard-ledger)))
    #+sbcl
    (let ((mutex (sb-thread:make-mutex :name "ethereum-lisp-node-store"))
          ;; A cons so SB-EXT:ATOMIC-INCF can update its fixnum CAR.
          (priority-waiters (list 0)))
      (flet ((hold (thunk)
               (call-with-devnet-store-guard-hold
                ledger release-hook long-hold-function thunk))
             (defer-to-priority ()
               ;; SBCL mutexes are not fair: a thread that releases the guard
               ;; and takes it again (a gap fill importing block after block,
               ;; a peer served lookup after lookup) usually wins against the
               ;; woken Engine waiter. Every non-Engine taker therefore stays
               ;; off the mutex while an Engine request waits, bounded by
               ;; *DEVNET-STORE-GUARD-PRIORITY-YIELD-SECONDS*.
               (when (plusp (car priority-waiters))
                 (let ((deadline
                         (+ (get-internal-real-time)
                            (* *devnet-store-guard-priority-yield-seconds*
                               internal-time-units-per-second))))
                   (loop while (and (plusp (car priority-waiters))
                                    (< (get-internal-real-time) deadline))
                         do (sleep 0.001))))))
        (values (lambda (thunk)
                  (defer-to-priority)
                  (sb-thread:with-mutex (mutex)
                    (hold thunk)))
                (lambda (thunk)
                  ;; A waiting Engine request counts as holding the guard.
                  (if (and (not (plusp (car priority-waiters)))
                           (sb-thread:grab-mutex mutex :waitp nil))
                      (unwind-protect (values (hold thunk) t)
                        (sb-thread:release-mutex mutex))
                      (values nil nil)))
                (lambda (thunk)
                  (let ((counted-p t)
                        (wait-started-at (get-internal-real-time))
                        (found-label
                          (devnet-store-guard-ledger-holder-label ledger)))
                    ;; Stamped on arrival, before any wait: readiness asks how
                    ;; long ago the consensus client last called, not how long
                    ;; ago one of its calls got the store.
                    (setf (devnet-store-guard-ledger-last-priority-at ledger)
                          wait-started-at)
                    (sb-ext:atomic-incf (car priority-waiters))
                    (unwind-protect
                         (flet ((owned ()
                                  (setf counted-p nil)
                                  (sb-ext:atomic-decf (car priority-waiters))
                                  (devnet-store-guard-note-priority-wait
                                   ledger wait-started-at found-label)
                                  (call-with-devnet-store-guard-hold
                                   ledger release-hook long-hold-function thunk
                                   :engine-p t)))
                           (let ((budget *devnet-engine-guard-busy-seconds*))
                             (if (null budget)
                                 (sb-thread:with-mutex (mutex) (owned))
                                 (devnet-store-guard-bounded-priority-wait
                                  mutex ledger budget wait-started-at
                                  found-label #'owned))))
                      ;; Unwound while still waiting (an interrupt, a timeout,
                      ;; or the bounded wait giving up).
                      (when counted-p
                        (sb-ext:atomic-decf (car priority-waiters))))))
                (lambda ()
                  (plusp (car priority-waiters)))
                ledger)))
    #-sbcl
    (flet ((hold (thunk)
             (call-with-devnet-store-guard-hold
              ledger release-hook long-hold-function thunk)))
      (values #'hold
              (lambda (thunk) (values (hold thunk) t))
              #'hold
              (lambda () nil)
              ledger))))

(defun devnet-node-store-guard-priority-pending-p (node)
  "True while an Engine request waits for NODE's store guard."
  (let ((pending (devnet-node-store-guard-priority-pending-function node)))
    (and pending (funcall pending) t)))

(defun devnet-node-yield-store-guard-to-priority (node)
  "Wait, WITHOUT holding NODE's store guard, until no Engine request waits.

A caller that just released the guard calls this before taking it again.
Returns when the last waiter owns the guard (it then serializes behind that
request's own work as usual) or after the bounded wait."
  (let ((deadline
          (+ (get-internal-real-time)
             (* *devnet-store-guard-priority-yield-seconds*
                internal-time-units-per-second))))
    (loop while (and (devnet-node-store-guard-priority-pending-p node)
                     (< (get-internal-real-time) deadline))
          do (sleep 0.001))))

(defun call-with-devnet-node-store-guard (node thunk)
  (unless (typep node 'devnet-node)
    (error "Devnet store guard requires a devnet node"))
  (unless (functionp thunk)
    (error "Devnet store guard requires a function"))
  (funcall (devnet-node-store-guard-function node) thunk))

(defun call-with-devnet-node-store-guard-as (node label thunk)
  "CALL-WITH-DEVNET-NODE-STORE-GUARD with the hold named LABEL, so a long hold
and an Engine request waiting behind it say what the holder was doing rather
than which thread it ran on (every peer session thread has the same name)."
  (let ((ethereum-lisp.telemetry:*telemetry-activity-label* label))
    (call-with-devnet-node-store-guard node thunk)))

(defun call-with-devnet-node-store-guard-if-free (node thunk)
  "Run THUNK under NODE's store guard only if the guard is free right now.

Returns (VALUES RESULT T) when THUNK ran and (VALUES NIL NIL) when the guard
was held. For callers that would rather have a stale answer than block: the
store guard is held for the whole of a block import, so a background thread
that waits on it does not run slowly, it stops until the node is idle.

Falls back to a blocking acquisition when the node has no try function, which
is what the non-SBCL build and any node built before this existed will have."
  (unless (typep node 'devnet-node)
    (error "Devnet store guard requires a devnet node"))
  (unless (functionp thunk)
    (error "Devnet store guard requires a function"))
  (let ((try (devnet-node-store-guard-try-function node)))
    (if (functionp try)
        (funcall try thunk)
        (values (call-with-devnet-node-store-guard node thunk) t))))

(defun call-with-devnet-peer-table (node thunk)
  "Run THUNK with exclusive access to NODE's peer table AND dial registry.

The two share one mutex on purpose: a scheduler decision reads both (is this
peer already connected? is there a free dial slot?) and then mutates both, and
that has to be one atomic step. It is independent of the store guard, so peer
bookkeeping never blocks behind block import or an RPC call.

The mutex is NOT recursive. Nothing called from inside THUNK may take it again --
which is why the peer table and the dial registry lock nothing themselves."
  (funcall (devnet-node-dial-guard-function node) thunk))

(defun devnet-node-metrics-enabled-p (node)
  "Whether --metrics is on.

Distinct from DEVNET-NODE-METRICS having a value: a node that has just started
with metrics on has counted nothing yet, so its snapshot is legitimately empty.
Anything deciding whether to publish metrics must ask this, not the counts."
  (counting-telemetry-sink-p (devnet-node-telemetry-sink node)))

(defun devnet-node-metrics (node)
  "Event counts collected since start, or NIL when --metrics is off.

These are counts of the telemetry events the node already emits, so they follow
whatever it really does rather than a separate set of counters that has to be
kept in step by hand."
  (let ((sink (devnet-node-telemetry-sink node)))
    (when (counting-telemetry-sink-p sink)
      (counting-telemetry-sink-snapshot sink))))

(defun devnet-node-metric-gauges (node)
  "Live operator levels sampled atomically enough for one Prometheus scrape."
  (let* ((store (devnet-node-store node))
         (head (chain-store-latest-block store))
         (safe (chain-store-safe-block store))
         (finalized (chain-store-finalized-block store)))
    `(("ethereum_lisp_txpool_pending"
       . ,(engine-payload-store-pending-transaction-count store))
      ("ethereum_lisp_txpool_queued"
       . ,(engine-payload-store-queued-transaction-count store))
      ("ethereum_lisp_txpool_basefee"
       . ,(engine-payload-store-basefee-transaction-count store))
      ("ethereum_lisp_txpool_blob"
       . ,(engine-payload-store-blob-transaction-count store))
      ("ethereum_lisp_chain_head_number"
       . ,(if head (block-header-number (block-header head)) 0))
      ("ethereum_lisp_chain_safe_number"
       . ,(if safe (block-header-number (block-header safe)) 0))
      ("ethereum_lisp_chain_finalized_number"
       . ,(if finalized (block-header-number (block-header finalized)) 0))
      ("ethereum_lisp_peer_count"
       . ,(devnet-peer-table-count (devnet-node-peer-table node)))
      ,@(devnet-node-operator-gauges node))))

;;;; RPC latency, recorded from the telemetry the HTTP handler already emits.
;;;;
;;;; Every served request ends in one `engine.rpc.http.request` event carrying
;;;; the JSON-RPC method names and `handlerMs`, the time from the end of the
;;;; request read to the response: guard wait, execution and encoding. A sink
;;;; layered under the counting sink keeps last, maximum, sum and count per
;;;; method family, so the metrics endpoint can say how long newPayload,
;;;; forkchoiceUpdated and getPayload take without any new instrumentation in
;;;; the Engine code.

(defparameter *devnet-rpc-latency-families*
  '("engine_new_payload" "engine_forkchoice_updated" "engine_get_payload"
    "engine_other" "rpc" "rpc_batch")
  "Every family the latency sink reports, in report order. Each is always
reported, zero until its first request, so a dashboard never sees a series
appear and vanish.")

(defstruct (devnet-rpc-latency-sink
            (:constructor make-devnet-rpc-latency-sink (&key delegate)))
  "A telemetry sink that records RPC handler latency, then passes events on."
  delegate
  (table (make-hash-table :test #'equal))
  #+sbcl (lock (sb-thread:make-mutex :name "devnet rpc latency sink")))

(defun devnet-rpc-latency-family (methods)
  "The latency family of METHODS, the comma-joined `rpcMethods` field."
  (flet ((prefix-p (prefix)
           (and (>= (length methods) (length prefix))
                (string= prefix methods :end2 (length prefix)))))
    (cond ((find #\, methods) "rpc_batch")
          ((prefix-p "engine_newPayload") "engine_new_payload")
          ((prefix-p "engine_forkchoiceUpdated") "engine_forkchoice_updated")
          ((and (prefix-p "engine_getPayload")
                (not (prefix-p "engine_getPayloadBodies")))
           "engine_get_payload")
          ((prefix-p "engine_") "engine_other")
          (t "rpc"))))

(defun devnet-rpc-latency-record (sink methods milliseconds)
  "Record one request of METHODS that took MILLISECONDS in its handler."
  (let ((family (devnet-rpc-latency-family methods)))
    (flet ((update ()
             (let ((entry (or (gethash family (devnet-rpc-latency-sink-table sink))
                              (setf (gethash family
                                             (devnet-rpc-latency-sink-table sink))
                                    (list :last 0 :max 0 :sum 0 :count 0)))))
               (setf (getf entry :last) milliseconds
                     (getf entry :max) (max milliseconds (getf entry :max))
                     (getf entry :sum) (+ milliseconds (getf entry :sum))
                     (getf entry :count) (1+ (getf entry :count)))
               (setf (gethash family (devnet-rpc-latency-sink-table sink))
                     entry))))
      #+sbcl (sb-thread:with-mutex ((devnet-rpc-latency-sink-lock sink))
               (update))
      #-sbcl (update))))

(defmethod telemetry-emit
    ((sink devnet-rpc-latency-sink) (event telemetry-event))
  (when (equal "engine.rpc.http.request" (telemetry-event-name event))
    (let* ((fields (telemetry-event-fields event))
           (methods (cdr (assoc "rpcMethods" fields :test #'equal)))
           (milliseconds (cdr (assoc "handlerMs" fields :test #'equal))))
      (when (and (stringp methods) (integerp milliseconds))
        (devnet-rpc-latency-record sink methods (max 0 milliseconds)))))
  (let ((delegate (devnet-rpc-latency-sink-delegate sink)))
    (when delegate (telemetry-emit delegate event)))
  event)

(defun devnet-rpc-latency-gauges (sink)
  "The latency gauges of SINK, every family, as (NAME . INTEGER) pairs."
  (let ((snapshot
          (flet ((copy ()
                   (loop for family in *devnet-rpc-latency-families*
                         collect (cons family
                                       (copy-list
                                        (gethash family
                                                 (devnet-rpc-latency-sink-table
                                                  sink)))))))
            #+sbcl (sb-thread:with-mutex ((devnet-rpc-latency-sink-lock sink))
                     (copy))
            #-sbcl (copy))))
    (loop for (family . entry) in snapshot
          append (loop for (key suffix) in '((:last "last_ms") (:max "max_ms")
                                             (:sum "ms_total")
                                             (:count "requests_total"))
                       collect (cons (format nil "ethereum_lisp_~A_~A"
                                             family suffix)
                                     (or (getf entry key) 0))))))

;;; DEVNET-NODE-RPC-LATENCY-SINK lives in observability.lisp, beside the sink
;;; layered above this one.

(defun devnet-node-enode (node)
  "Our own enode URL, or NIL when we are not listening.

The address is the one a peer could actually dial: a wildcard bind reports as
loopback rather than advertising 0.0.0.0, which is not an address."
  (let ((port (devnet-node-p2p-port node)))
    (when port
      (enode-url (node-id-from-private-key (devnet-node-node-key node))
                 (devnet-node-advertised-host node)
                 port))))

(defun devnet-node-advertised-host (node)
  (let ((policy (devnet-node-nat-policy node)))
    (if (and policy (eq :extip (ethereum-lisp.nat:nat-policy-mode policy)))
        (ethereum-lisp.nat:nat-policy-address policy)
        (eth-sync-socket-endpoint-host
         (or (devnet-node-p2p-host node) "0.0.0.0")))))

(defun devnet-node-engine-cors-origins (node)
  (devnet-endpoint-config-cors-origins
   (devnet-node-engine-endpoint-config node)))

(defun devnet-node-public-cors-origins (node)
  (devnet-endpoint-config-cors-origins
   (devnet-node-public-endpoint-config node)))

(defun devnet-node-engine-vhosts (node)
  (devnet-endpoint-config-allowed-hosts
   (devnet-node-engine-endpoint-config node)))

(defun devnet-node-public-vhosts (node)
  (devnet-endpoint-config-allowed-hosts
   (devnet-node-public-endpoint-config node)))

(defun devnet-node-allow-unprotected-transactions-p (node)
  (devnet-txpool-policy-allow-unprotected-transactions-p
   (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-price-limit (node)
  (devnet-txpool-policy-price-limit (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-price-bump-percent (node)
  (devnet-txpool-policy-price-bump-percent (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-account-slot-limit (node)
  (devnet-txpool-policy-account-slot-limit (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-global-slot-limit (node)
  (devnet-txpool-policy-global-slot-limit (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-account-queue-limit (node)
  (devnet-txpool-policy-account-queue-limit (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-global-queue-limit (node)
  (devnet-txpool-policy-global-queue-limit (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-local-addresses (node)
  (devnet-txpool-policy-local-addresses (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-no-local-exemptions-p (node)
  (devnet-txpool-policy-no-local-exemptions-p
   (devnet-node-txpool-policy node)))

(defun devnet-node-txpool-lifetime-seconds (node)
  (devnet-txpool-policy-lifetime-seconds (devnet-node-txpool-policy node)))

(defstruct devnet-shutdown-controller
  requested-p
  engine-listener
  public-listener
  ;; Anything else that must be closed to wake a thread blocked on it, as an
  ;; alist of (token . thunk) under CLOSEABLE-LOCK. The two listener slots above
  ;; predate this and stay as they are; peer sockets, which come and go, ride
  ;; here. See DEVNET-SHUTDOWN-CONTROLLER-ADD-CLOSEABLE.
  (closeables '())
  (closeable-counter 0)
  (closeable-lock (devnet-make-mutex "ethereum-lisp-devnet-closeables")))

(defstruct (devnet-rejournal-state
            (:constructor %make-devnet-rejournal-state
                (&key node interval-seconds now-function last-run-time)))
  node
  interval-seconds
  now-function
  last-run-time)

(defstruct (devnet-dev-period-state
            (:constructor %make-devnet-dev-period-state
                (&key node interval-seconds now-function last-run-time)))
  node
  interval-seconds
  now-function
  last-run-time)

(defconstant +devnet-default-public-rpc-port+ 8545)
(defparameter +devnet-datadir-database-file+ "ethereum-lisp-chain.sexp")
(defparameter +devnet-datadir-rocksdb-directory+ "chaindata/"
  "Datadir-relative directory holding the RocksDB chain database when the
--db.engine=rocksdb backend is selected. RocksDB owns a directory of SST and
WAL files rather than the single CRC-framed log file the default backend uses.")
(defparameter +devnet-datadir-genesis-file+ "genesis.json")
(defparameter +devnet-datadir-jwt-secret-file+ "jwtsecret")
(defparameter +devnet-geth-datadir-directory+ "geth/")
(defparameter +devnet-datadir-node-key-file+ "nodekey")
(defparameter +devnet-datadir-enr-seq-file+ "enrseq")
(defparameter +devnet-datadir-dns-seq-file+ "dnsseq")
(defconstant +devnet-default-dev-gas-limit+ #x1c9c380)
(defconstant +devnet-default-miner-gas-limit+ 60000000
  "Default builder gas ceiling from geth 38271784 miner.DefaultConfig.")

(defun devnet-cli-miner-gas-limit (options)
  (or (getf options :miner-gas-limit)
      +devnet-default-miner-gas-limit+))

(defun devnet-cli-dev-genesis-json (&key
                                      (gas-limit
                                       +devnet-default-dev-gas-limit+)
                                      (coinbase (zero-address)))
  (concatenate
   'string
   "{"
   "\"config\":{\"chainId\":1337,\"terminalTotalDifficulty\":0,"
   "\"londonBlock\":0,\"shanghaiTime\":0},"
   "\"nonce\":\"0x0\","
   "\"timestamp\":\"0x0\","
   "\"extraData\":\"0x\","
   "\"gasLimit\":\"" (quantity-to-hex gas-limit) "\","
   "\"difficulty\":\"0x0\","
   "\"mixHash\":\"0x0000000000000000000000000000000000000000000000000000000000000000\","
   "\"coinbase\":\"" (address-to-hex coinbase) "\","
   "\"stateRoot\":\"0x23cc0c47d1238030e9c1ec18013dcb17024d3d42729567adbb6406a64d3007f3\","
   "\"alloc\":{"
   "\"0x0000000000000000000000000000000000001001\":{"
   "\"balance\":\"0xde0b6b3a7640000\",\"nonce\":\"0x1\"},"
   "\"0x0000000000000000000000000000000000001002\":{"
   "\"balance\":\"0x5\",\"code\":\"0x6001600055\","
   "\"storage\":{\"0x00\":\"0x2a\",\"0x01\":\"0x00\"}}"
   "}}"))

(defun devnet-process-id ()
  #+sbcl
  (sb-unix:unix-getpid)
  #-sbcl
  nil)

(defun devnet-shutdown-requested-p (controller)
  (and controller
       (devnet-shutdown-controller-requested-p controller)))

(defun devnet-notify-background-worker (notification)
  "Record one bounded worker wakeup and notify its condition variable."
  #-sbcl
  (declare (ignore notification))
  #-sbcl
  nil
  #+sbcl
  (sb-thread:with-mutex
      ((devnet-coalesced-notification-lock notification))
    (setf (devnet-coalesced-notification-pending-p notification) t)
    (sb-thread:condition-broadcast
     (devnet-coalesced-notification-changed notification))
    t))

(defun devnet-consume-background-worker-notification (notification)
  "Consume NOTIFICATION's coalesced wakeup, returning whether one existed."
  #-sbcl
  (declare (ignore notification))
  #-sbcl
  nil
  #+sbcl
  (sb-thread:with-mutex
      ((devnet-coalesced-notification-lock notification))
    (prog1 (devnet-coalesced-notification-pending-p notification)
      (setf (devnet-coalesced-notification-pending-p notification) nil))))

(defun devnet-wait-for-background-worker-notification
    (notification shutdown-controller timeout-seconds)
  "Wait for a notification, shutdown, or the periodic fallback timeout."
  #-sbcl
  (declare (ignore notification shutdown-controller timeout-seconds))
  #-sbcl
  :timeout
  #+sbcl
  (sb-thread:with-mutex
      ((devnet-coalesced-notification-lock notification))
    (unless (or (devnet-coalesced-notification-pending-p notification)
                (devnet-shutdown-requested-p shutdown-controller))
      (sb-thread:condition-wait
       (devnet-coalesced-notification-changed notification)
       (devnet-coalesced-notification-lock notification)
       :timeout timeout-seconds))
    (cond
      ((devnet-shutdown-requested-p shutdown-controller) :shutdown)
      ((devnet-coalesced-notification-pending-p notification)
       (setf (devnet-coalesced-notification-pending-p notification) nil)
       :notified)
      (t :timeout))))

(defun devnet-node-notify-sync-coordinator (node)
  "Record one bounded coordinator wakeup and notify its condition variable.

Repeated peer announcements coalesce into the same PENDING-P bit.  The caller
does not hold the peer-table or store guard while taking this independent lock."
  (devnet-notify-background-worker
   (devnet-node-sync-notification node)))

(defun devnet-node-notify-payload-improvement (node)
  "Wake the payload builder after FCU publishes an open payload."
  (devnet-notify-background-worker
   (devnet-node-payload-improvement-notification node)))

(defun devnet-node-consume-sync-notification (node)
  "Consume NODE's coalesced coordinator wakeup, returning whether one existed."
  (devnet-consume-background-worker-notification
   (devnet-node-sync-notification node)))

(defun devnet-node-wait-for-sync-notification
    (node shutdown-controller timeout-seconds)
  "Wait for an announcement, shutdown, or the periodic fallback timeout.

The predicate and wait share one mutex, so a notification between the sync pass
and this call remains pending instead of being lost before CONDITION-WAIT."
  (devnet-wait-for-background-worker-notification
   (devnet-node-sync-notification node)
   shutdown-controller
   timeout-seconds))

(defun devnet-node-wait-for-payload-improvement
    (node shutdown-controller timeout-seconds)
  "Wait for an Engine payload request, shutdown, or the fallback timeout."
  (devnet-wait-for-background-worker-notification
   (devnet-node-payload-improvement-notification node)
   shutdown-controller
   timeout-seconds))

(defun devnet-shutdown-controller-register-listeners
    (controller engine-listener public-listener)
  (unless (typep controller 'devnet-shutdown-controller)
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (setf (devnet-shutdown-controller-engine-listener controller) engine-listener
        (devnet-shutdown-controller-public-listener controller) public-listener)
  controller)

(defun devnet-shutdown-controller-add-closeable (controller thunk)
  "Register THUNK to be run when shutdown is requested, and return a token for
DEVNET-SHUTDOWN-CONTROLLER-REMOVE-CLOSEABLE.

If shutdown has ALREADY been requested the thunk is run immediately and NIL is
returned. Without that, a thread registering its socket a moment after the sweep
would never be closed and would block on a read forever, which is precisely the
shutdown a caller was trying to perform."
  (unless (typep controller 'devnet-shutdown-controller)
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (let ((token
          (call-with-devnet-mutex
           (devnet-shutdown-controller-closeable-lock controller)
           (lambda ()
             (unless (devnet-shutdown-controller-requested-p controller)
               (let ((token (incf (devnet-shutdown-controller-closeable-counter
                                   controller))))
                 (push (cons token thunk)
                       (devnet-shutdown-controller-closeables controller))
                 token))))))
    (unless token
      (ignore-errors (funcall thunk)))
    token))

(defun devnet-shutdown-controller-remove-closeable (controller token)
  "Forget the closeable registered under TOKEN, without running it."
  (unless (typep controller 'devnet-shutdown-controller)
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (when token
    (call-with-devnet-mutex
     (devnet-shutdown-controller-closeable-lock controller)
     (lambda ()
       (setf (devnet-shutdown-controller-closeables controller)
             (remove token (devnet-shutdown-controller-closeables controller)
                     :key #'car)))))
  t)

(defun devnet-shutdown-request (controller)
  (unless (typep controller 'devnet-shutdown-controller)
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (setf (devnet-shutdown-controller-requested-p controller) t)
  (let ((engine-listener
          (devnet-shutdown-controller-engine-listener controller))
        (public-listener
          (devnet-shutdown-controller-public-listener controller)))
    (when engine-listener
      (ignore-errors
       (engine-rpc-http-listener-close engine-listener)))
    (when public-listener
      (ignore-errors
       (engine-rpc-http-listener-close public-listener))))
  ;; Snapshot under the lock, then close OUTSIDE it. Closing while holding it
  ;; would block every session thread trying to deregister — and those threads
  ;; are exactly what the caller is about to wait for.
  (let ((closeables
          (call-with-devnet-mutex
           (devnet-shutdown-controller-closeable-lock controller)
           (lambda ()
             (prog1 (devnet-shutdown-controller-closeables controller)
               (setf (devnet-shutdown-controller-closeables controller) '()))))))
    (dolist (entry closeables)
      (ignore-errors (funcall (cdr entry)))))
  t)

(defparameter *devnet-shutdown-join-budget-seconds* 12
  "Seconds that ALL of a serving node's worker joins may take together.

A supervisor such as `docker stop` sends SIGKILL a fixed grace period after
SIGTERM (30 s by default). The joins share this one budget rather than each
carrying its own bound, because bounds that each look short add up: before the
budget, a node whose sync coordinator ignored the stop spent 15 s on that join
alone and then 5 s or more on each later one. What is left of the grace period
after the joins belongs to the shutdown export and the store close, which
waits up to five seconds for the store's users and two for RocksDB's pools.")

(defconstant +devnet-shutdown-terminate-grace-seconds+ 1/10
  "How long a worker that missed the join deadline has to unwind once it is
terminated, before it is abandoned.")

(defun devnet-shutdown-join-deadline
    (&optional (budget-seconds *devnet-shutdown-join-budget-seconds*))
  "The internal-real-time at which a shutdown stops waiting for its workers."
  (unless (and (realp budget-seconds) (plusp budget-seconds))
    (error "Devnet shutdown join budget must be a positive number of seconds"))
  (+ (get-internal-real-time)
     (ceiling (* budget-seconds internal-time-units-per-second))))

(defun devnet-shutdown-seconds-left (deadline)
  "Seconds until DEADLINE, never below a millisecond.

SB-THREAD:JOIN-THREAD rejects a zero timeout with a TYPE-ERROR, so an expired
deadline still polls the thread once instead of signalling."
  (max 1/1000
       (/ (- deadline (get-internal-real-time))
          internal-time-units-per-second)))

(defun devnet-join-worker-by-deadline
    (thread deadline label &key (stream *error-output*))
  "Join THREAD by DEADLINE; past it, terminate THREAD and abandon it.

Returns :ABSENT for a NIL thread, :JOINED when it stopped by itself, and
:TERMINATED when it stopped within +DEVNET-SHUTDOWN-TERMINATE-GRACE-SECONDS+
of SB-THREAD:TERMINATE-THREAD. Otherwise reports LABEL on STREAM and returns
:ABANDONED: the shutdown goes on to the export and the store close, whose own
drain waits for any user still inside the store handle."
  #-sbcl
  (declare (ignore thread deadline label stream))
  #-sbcl
  :absent
  #+sbcl
  (cond
    ((null thread) :absent)
    ((not (eq :timeout
              (nth-value 1 (sb-thread:join-thread
                            thread
                            :timeout (devnet-shutdown-seconds-left deadline)
                            :default nil))))
     :joined)
    (t
     (ignore-errors (sb-thread:terminate-thread thread))
     ;; Terminating unwinds at the thread's next safepoint; a thread inside a
     ;; foreign call or WITHOUT-INTERRUPTS gets there only when it leaves it.
     ;; The join above timed out AT the deadline, so what is left of it is
     ;; nothing: give the unwind a short fixed grace instead. Each stuck
     ;; worker can thus overrun the deadline by at most that grace.
     (if (eq :timeout
             (nth-value 1 (sb-thread:join-thread
                           thread
                           :timeout
                           (max (devnet-shutdown-seconds-left deadline)
                                +devnet-shutdown-terminate-grace-seconds+)
                           :default nil)))
         (progn
           (ignore-errors
            (format stream
                    "Devnet shutdown abandoned worker ~A: it did not stop ~
                     within the shared worker join deadline.~%"
                    label)
            (finish-output stream))
           :abandoned)
         :terminated))))

(defun devnet-signal-number (name)
  #+sbcl
  (let* ((package (find-package "SB-UNIX"))
         (symbol (and package (find-symbol name package))))
    (unless (and symbol (boundp symbol))
      (error "SBCL signal ~A is not available" name))
    (symbol-value symbol))
  #-sbcl
  (declare (ignore name))
  #-sbcl
  nil)

(defun call-with-devnet-shutdown-signal-handlers
    (controller thunk &key (stream *error-output*))
  (unless (typep controller 'devnet-shutdown-controller)
    (error "Devnet shutdown controller must be devnet-shutdown-controller"))
  (unless (functionp thunk)
    (error "Devnet shutdown signal thunk must be a function"))
  #-sbcl
  (declare (ignore controller stream))
  #-sbcl
  (funcall thunk)
  #+sbcl
  (let ((sigint (devnet-signal-number "SIGINT"))
        (sigterm (devnet-signal-number "SIGTERM")))
    (flet ((request-shutdown (&rest ignored)
             (declare (ignore ignored))
             (format stream "Devnet shutdown requested; closing RPC listeners.~%")
             (devnet-shutdown-request controller)))
      (unwind-protect
           (progn
             (sb-sys:enable-interrupt sigint #'request-shutdown)
             (sb-sys:enable-interrupt sigterm #'request-shutdown)
             (funcall thunk))
        (sb-sys:enable-interrupt sigint :default)
        (sb-sys:enable-interrupt sigterm :default)))))
