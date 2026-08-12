(in-package #:ethereum-lisp.cli)

;;;; Who to dial next, and when.
;;;;
;;;; Outbound peering needs state the peer table deliberately does not hold: a
;;;; peer we are not connected to, have never connected to, or failed to reach
;;;; four times running. Keeping that here rather than as "dialing" entries in
;;;; the peer table is not tidiness. A dial that fails never reaches a session
;;;; teardown, so an entry created when the dial started would never be removed
;;;; — it would hold a peer slot and block redial of that identity forever. And
;;;; a failed dial is the COMMON case: discovery returns every node it has seen,
;;;; not only the ones that answered.
;;;;
;;;; TWO RULES THAT ARE NOT OBVIOUS:
;;;;
;;;; 1. THE COOLDOWN IS STAMPED WHEN A DIAL STARTS, not when it ends. That one
;;;;    choice makes a clean disconnect, a failed dial, and a refusal all behave
;;;;    correctly with no per-outcome arithmetic: a peer we held for an hour is
;;;;    instantly redialable because its cooldown expired 59 minutes ago, while
;;;;    a peer that drops us every two seconds is throttled by the same rule.
;;;;
;;;; 2. NOTHING IN THIS FILE LOCKS ANYTHING, and nothing reads a clock — NOW is
;;;;    always an argument. The registry and the peer table are guarded by ONE
;;;;    non-recursive mutex, so a caller composes several of these primitives
;;;;    inside a single acquisition. If a lock ever appears in this file, two of
;;;;    them will end up nested and that mutex signals rather than waits.
;;;;
;;;; HOW MANY OUTBOUND PEERS WE HOLD HAS EXACTLY ONE AUTHORITY: the peer table.
;;;; A candidate's :CONNECTED state is an ownership marker so we do not redial
;;;; someone we are already talking to; it is never counted. Counting it would
;;;; give two sources of truth that drift the first time a session thread dies
;;;; between admission and completion.

(defconstant +devnet-dial-cooldown-seconds+ 35
  "Base wait between dials of one peer, measured from when the dial STARTED.
Our policy. Long enough that two nodes which dialed each other simultaneously
and both dropped resolve on the next round rather than spinning. If a
per-source-IP inbound throttle is ever added, its window must be strictly
SHORTER than this, or two ethereum-lisp nodes will livelock refusing each other.")

(defconstant +devnet-dial-backoff-ceiling-seconds+ 300
  "Longest a repeatedly failing peer waits. Our policy: the ceiling is what
keeps escalating backoff from becoming permanent abandonment.")

(defconstant +devnet-dial-backoff-max-doublings+ 4
  "How many times the cooldown may double. Our policy.")

(defconstant +devnet-max-active-dials+ 8
  "Hard cap on dials in flight, whatever the peer limit implies. Our policy:
at --maxpeers 60 the ratio below would otherwise authorise 20 dial threads.")

(defconstant +devnet-dial-ratio+ 3
  "One in this many peer slots may be filled by dialing. Our policy, and the
reason it exists: a node that dials until it is full has no room left to be
reached from outside, which is the whole thing the inbound wave was built for.")

(defconstant +devnet-dial-dynamic-candidate-limit+ 256
  "How many discovered candidates we remember. Our policy — the bound that the
old dial registry, a table only ever added to, did not have.")

(defconstant +devnet-dial-dynamic-forget-failures+ 3
  "After this many failures a DISCOVERED candidate is forgotten. A configured
--peer is never forgotten, however often it fails: the operator asked for it.")

(defstruct (devnet-dial-candidate
            (:constructor make-devnet-dial-candidate
                (&key id-hex enode (kind :dynamic) (state :idle) (failures 0)
                      (next-eligible-at 0) dial-started-at last-error)))
  "One peer we might dial. KIND is :STATIC (an operator's --peer), :BOOTSTRAP
(a preset or --bootnodes seed), or :DYNAMIC (discovered). Static and bootstrap
candidates are never forgotten. STATE is :IDLE, :DIALING or :CONNECTED."
  id-hex
  enode
  kind
  state
  failures
  next-eligible-at
  dial-started-at
  last-error)

(defstruct (devnet-dial-registry
            (:constructor %make-devnet-dial-registry
                (candidates base-cooldown ceiling max-doublings max-active-dials)))
  "Every peer we might dial, keyed by the same hex node id the peer table uses,
so a peer that dials us while we are dialing it is recognised as one peer.

The tuning slots exist so a test can drive a redial with small numbers instead
of sleeping thirty-five seconds."
  candidates
  base-cooldown
  ceiling
  max-doublings
  max-active-dials)

(defun make-devnet-dial-registry
    (&key (base-cooldown +devnet-dial-cooldown-seconds+)
          (ceiling +devnet-dial-backoff-ceiling-seconds+)
          (max-doublings +devnet-dial-backoff-max-doublings+)
          (max-active-dials +devnet-max-active-dials+))
  (%make-devnet-dial-registry (make-hash-table :test #'equal)
                              base-cooldown ceiling max-doublings
                              max-active-dials))

(defun devnet-dial-registry-candidate (registry id-hex)
  (gethash id-hex (devnet-dial-registry-candidates registry)))

(defun devnet-dial-registry-count (registry)
  (hash-table-count (devnet-dial-registry-candidates registry)))

(defun devnet-dial-backoff-seconds (registry failures)
  "How long to wait before dialing a peer that has failed FAILURES times."
  (min (devnet-dial-registry-ceiling registry)
       (* (devnet-dial-registry-base-cooldown registry)
          (ash 1 (min failures (devnet-dial-registry-max-doublings registry))))))

(defun devnet-dial-registry-put-static (registry id-hex enode)
  "Record an operator-configured peer, idempotently.

An existing candidate keeps its state, failure count and cooldown, so re-reading
the configured peers on every tick never resets a peer that is cooling down. A
discovered candidate is promoted to static."
  (let ((existing (devnet-dial-registry-candidate registry id-hex)))
    (cond
      (existing
       (setf (devnet-dial-candidate-kind existing) :static)
       (setf (devnet-dial-candidate-enode existing) enode)
       existing)
      (t
       (setf (gethash id-hex (devnet-dial-registry-candidates registry))
             (make-devnet-dial-candidate :id-hex id-hex :enode enode
                                         :kind :static))))))

(defun devnet-dial-registry-put-bootstrap (registry id-hex enode)
  "Record a discovery bootstrap node as a persistent fallback dial candidate.

Bootnodes are not operator-configured static peers, but public presets must be
able to dial them when the discovered table is sparse.  Re-reading one keeps
its cooldown and failure history.  A peer already promoted to :STATIC by
admin_addPeer remains static."
  (let ((existing (devnet-dial-registry-candidate registry id-hex)))
    (cond
      (existing
       (unless (eq :static (devnet-dial-candidate-kind existing))
         (setf (devnet-dial-candidate-kind existing) :bootstrap))
       (setf (devnet-dial-candidate-enode existing) enode)
       existing)
      (t
       (setf (gethash id-hex (devnet-dial-registry-candidates registry))
             (make-devnet-dial-candidate :id-hex id-hex :enode enode
                                         :kind :bootstrap))))))

(defun devnet-dial-registry-offer-dynamic (registry id-hex enode)
  "Record a discovered peer, returning T only if it was new.

Never disturbs an existing candidate, and refuses once the registry is full —
discovery produces an unbounded stream, most of it unreachable."
  (unless (or (devnet-dial-registry-candidate registry id-hex)
              (>= (devnet-dial-registry-count registry)
                  +devnet-dial-dynamic-candidate-limit+))
    (setf (gethash id-hex (devnet-dial-registry-candidates registry))
          (make-devnet-dial-candidate :id-hex id-hex :enode enode
                                      :kind :dynamic))
    t))

(defun devnet-dial-registry-dialing-count (registry)
  "How many dials are in flight. NOT how many outbound peers we hold — that is
the peer table's to answer."
  (let ((count 0))
    (maphash (lambda (id candidate)
               (declare (ignore id))
               (when (eq :dialing (devnet-dial-candidate-state candidate))
                 (incf count)))
             (devnet-dial-registry-candidates registry))
    count))

(defun devnet-dial-max-peers (table)
  "How many peers we may hold outbound. Zero when peering is off entirely."
  (let ((max-peers (devnet-peer-table-max-peers table)))
    (if (plusp max-peers)
        (max 1 (floor max-peers +devnet-dial-ratio+))
        0)))

(defun devnet-dial-free-slots (registry table)
  "How many new dials may start right now."
  (max 0 (- (min (devnet-dial-registry-max-active-dials registry)
                 (- (devnet-dial-max-peers table)
                    (devnet-peer-table-count-by-direction table :outbound)))
            (devnet-dial-registry-dialing-count registry))))

(defun devnet-dial-verdict (registry table id-hex now)
  "Whether to dial ID-HEX, and if not, why not.

Returns :DIAL, :SELF, :ALREADY-DIALING, :ALREADY-CONNECTED, :COOLING-DOWN,
:NO-SLOT or :UNKNOWN. The clause order is the policy, and the reason returned is
what an operator sees, so a peer that is both ourselves and cooling down reports
:SELF.

The :ALREADY-CONNECTED clause asks the peer table without regard to direction,
and that is what dedups a peer which dialed us while we were dialing it."
  (let ((candidate (devnet-dial-registry-candidate registry id-hex)))
    (cond
      ((null candidate) :unknown)
      ((equal id-hex (devnet-peer-table-self-id-hex table)) :self)
      ((eq :dialing (devnet-dial-candidate-state candidate)) :already-dialing)
      ((devnet-peer-table-entry table id-hex) :already-connected)
      ((< now (devnet-dial-candidate-next-eligible-at candidate)) :cooling-down)
      ((zerop (devnet-dial-free-slots registry table)) :no-slot)
      (t :dial))))

(defun devnet-dial-candidate-order (a b)
  "Configured peers, then bootnodes, then discovered peers; within one class,
order by eligibility and identity so hash iteration never affects the plan."
  (flet ((rank (candidate)
           (ecase (devnet-dial-candidate-kind candidate)
             (:static 0)
             (:bootstrap 1)
             (:dynamic 2))))
    (let ((a-rank (rank a))
          (b-rank (rank b)))
      (cond
        ((< a-rank b-rank) t)
        ((> a-rank b-rank) nil)
        ((/= (devnet-dial-candidate-next-eligible-at a)
             (devnet-dial-candidate-next-eligible-at b))
         (< (devnet-dial-candidate-next-eligible-at a)
            (devnet-dial-candidate-next-eligible-at b)))
        (t (string< (devnet-dial-candidate-id-hex a)
                    (devnet-dial-candidate-id-hex b)))))))

(defun devnet-dial-registry-plan (registry table now)
  "The candidates to dial now, in a deterministic order, within the slot budget.

Mutates nothing, so it can be checked on its own."
  (let ((eligible '()))
    (maphash (lambda (id candidate)
               (when (eq :dial (devnet-dial-verdict registry table id now))
                 (push candidate eligible)))
             (devnet-dial-registry-candidates registry))
    (let ((ordered (sort eligible #'devnet-dial-candidate-order))
          (slots (devnet-dial-free-slots registry table)))
      (subseq ordered 0 (min (length ordered) slots)))))

(defun devnet-dial-registry-mark-dialing (registry id-hex now)
  "Claim a candidate for a dial that is about to start.

The cooldown is stamped HERE, at the start — see rule 1 in the file header."
  (let ((candidate (devnet-dial-registry-candidate registry id-hex)))
    (when candidate
      (setf (devnet-dial-candidate-state candidate) :dialing)
      (setf (devnet-dial-candidate-dial-started-at candidate) now)
      (setf (devnet-dial-candidate-next-eligible-at candidate)
            (+ now (devnet-dial-backoff-seconds
                    registry (devnet-dial-candidate-failures candidate))))
      candidate)))

(defun devnet-dial-registry-claim-plan (registry table now)
  "Plan the next dials AND claim them, as one step.

One call rather than two because the decision and the claim must not be
separable: two threads planning against the same free slot would both dial."
  (let ((plan (devnet-dial-registry-plan registry table now)))
    (dolist (candidate plan plan)
      (devnet-dial-registry-mark-dialing
       registry (devnet-dial-candidate-id-hex candidate) now))))

(defun devnet-dial-registry-mark-connected (registry id-hex now)
  "Note that a dial became a peer. Ownership only; never counted."
  (declare (ignore now))
  (let ((candidate (devnet-dial-registry-candidate registry id-hex)))
    (when candidate
      (setf (devnet-dial-candidate-state candidate) :connected)
      candidate)))

(defun devnet-dial-registry-mark-done (registry id-hex now &key (outcome :failed)
                                                                error)
  "Release a candidate whose dial or session has ended.

OUTCOME :DISCONNECTED means we held the peer and it ended, so the failure count
resets and the peer becomes eligible again one base cooldown after the dial
STARTED — which for any session longer than that is already in the past. That is
redial-after-disconnect, stated rather than left to emerge.

:FAILED and :REFUSED both count a failure and back off, deliberately with the
same arithmetic: distinguishing a refusal from an unreachable host is a
refinement we cut, and the disconnect reason is on the condition if it is ever
wanted. Idempotent for a candidate already idle."
  (let ((candidate (devnet-dial-registry-candidate registry id-hex)))
    (when candidate
      (let ((started (or (devnet-dial-candidate-dial-started-at candidate) now)))
        (ecase outcome
          (:disconnected
           (setf (devnet-dial-candidate-failures candidate) 0)
           (setf (devnet-dial-candidate-next-eligible-at candidate)
                 (+ started (devnet-dial-registry-base-cooldown registry))))
          ((:failed :refused)
           (incf (devnet-dial-candidate-failures candidate))
           (setf (devnet-dial-candidate-next-eligible-at candidate)
                 (+ started (devnet-dial-backoff-seconds
                             registry
                             (devnet-dial-candidate-failures candidate)))))))
      (setf (devnet-dial-candidate-state candidate) :idle)
      (setf (devnet-dial-candidate-last-error candidate) error)
      candidate)))

(defun devnet-dial-registry-expire (registry now)
  "Forget discovered candidates that have failed too often, and return how many.

Configured peers are never forgotten. This is what bounds the registry against
a discovery stream that is mostly unreachable hosts."
  (let ((doomed '()))
    (maphash (lambda (id candidate)
               (when (and (eq :dynamic (devnet-dial-candidate-kind candidate))
                          (eq :idle (devnet-dial-candidate-state candidate))
                          (>= (devnet-dial-candidate-failures candidate)
                              +devnet-dial-dynamic-forget-failures+)
                          (>= now (devnet-dial-candidate-next-eligible-at
                                   candidate)))
                 (push id doomed)))
             (devnet-dial-registry-candidates registry))
    (dolist (id doomed (length doomed))
      (remhash id (devnet-dial-registry-candidates registry)))))

(defun devnet-dial-registry-snapshot (registry)
  "The candidates as plists, for tests and reporting."
  (let ((entries '()))
    (maphash (lambda (id candidate)
               (declare (ignore id))
               (push (list :id (devnet-dial-candidate-id-hex candidate)
                           :enode (devnet-dial-candidate-enode candidate)
                           :kind (devnet-dial-candidate-kind candidate)
                           :state (devnet-dial-candidate-state candidate)
                           :failures (devnet-dial-candidate-failures candidate)
                           :next-eligible-at
                           (devnet-dial-candidate-next-eligible-at candidate))
                     entries))
             (devnet-dial-registry-candidates registry))
    (sort entries #'string< :key (lambda (entry) (getf entry :id)))))
