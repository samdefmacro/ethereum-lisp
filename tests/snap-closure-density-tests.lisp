(in-package #:ethereum-lisp.test)

;;;; The closed account writer at production page density.
;;;;
;;;; SNAP-CLOSED-ACCOUNT-WRITER-PERSISTS-MOST-OF-THE-ACCOUNT-TRIE measures the
;;;; writer on sixteen accounts, where every interior node straddles a task
;;;; boundary.  What decides whether healing converges on a public network is
;;;; the withheld fraction at live density -- hundreds of accounts per
;;;; AccountRange page, a contract population with small storage and a tail of
;;;; byte-capped giants -- and, above all, what the healer must then walk after
;;;; a pivot rebase in the middle of the range download.  This file builds such
;;;; a state deterministically (seeded PRNG, no randomness in any assertion),
;;;; imports it through the production importers, and attributes every
;;;; withheld account node to the reason it was withheld.

;;; ------------------------------------------------------------------
;;; Deterministic synthetic state
;;; ------------------------------------------------------------------

(defun make-snap-density-prng (seed)
  "Return a deterministic PRNG closure: (funcall prng bound) => [0, bound).

A 64-bit linear congruential generator (Knuth's MMIX constants) whose high
bits are reduced modulo BOUND.  Deterministic across images and runs, which is
the whole point: the fixture is data, not a sample."
  (let ((state (ldb (byte 64 0) (+ 1442695040888963407 (* 7919 seed)))))
    (lambda (bound)
      (setf state (ldb (byte 64 0)
                       (+ (* state 6364136223846793005) 1442695040888963407)))
      (mod (ash state -24) bound))))

(defun snap-density-code (index)
  "Return distinct deterministic bytecode number INDEX."
  (concatenate 'vector
               (make-byte-vector 8 :initial-element (mod index 251))
               (integer-to-minimal-bytes (+ 65536 index))
               #(96 0 96 0 243)))

(defun snap-density-address (index)
  (snap-test-address-from-integer (+ 1000000 index)))

(defun snap-density-slot (account-index slot)
  (make-hash32 (snap-test-index-hash (+ (* account-index 4096) slot))))

(defun snap-density-state
    (count &key (seed 1) (contract-percent 15) (storageless-percent 20)
                (big-contracts 3) (big-slots-min 1000) (big-slots-spread 1000))
  "Return a state of COUNT accounts shaped like a live account trie.

CONTRACT-PERCENT of the accounts carry bytecode drawn from a pool of one code
per eight contracts (proxies and clones share code on a real chain).  Of the
contracts, STORAGELESS-PERCENT own no storage and the rest own one to eight
slots, except BIG-CONTRACTS spread evenly through the contract population,
which own BIG-SLOTS-MIN plus up to BIG-SLOTS-SPREAD slots -- wide enough that a
realistic StorageRanges byte cap chunks them.

Values: the state, the vector of account indices that are contracts, and a
plist of population counts."
  (let* ((prng (make-snap-density-prng seed))
         (state (make-state-db))
         (contracts '())
         (slots-total 0)
         (storage-accounts 0))
    (dotimes (index count)
      (state-db-set-account
       state (snap-density-address index)
       (make-state-account
        :nonce (funcall prng 5000)
        :balance (+ 1 (funcall prng (ash 1 60)))))
      (when (< (funcall prng 100) contract-percent)
        (push index contracts)))
    (setf contracts (coerce (nreverse contracts) 'vector))
    (let* ((contract-count (length contracts))
           (pool (max 4 (floor contract-count 8)))
           (big (make-hash-table)))
      (dotimes (j (min big-contracts contract-count))
        (setf (gethash (floor (* (+ j 1/2) contract-count)
                              (max 1 big-contracts))
                       big)
              t))
      (dotimes (position contract-count)
        (let* ((index (aref contracts position))
               (address (snap-density-address index))
               (slots
                 (cond
                   ((gethash position big)
                    (+ big-slots-min (funcall prng (1+ big-slots-spread))))
                   ((< (funcall prng 100) storageless-percent) 0)
                   (t (1+ (funcall prng 8))))))
          (state-db-set-code state address
                             (snap-density-code (funcall prng pool)))
          (when (plusp slots)
            (incf storage-accounts)
            (incf slots-total slots))
          (loop for slot from 1 to slots
                do (state-db-set-storage
                    state address (snap-density-slot index slot)
                    (+ 1 (funcall prng (ash 1 64))))))))
    (values state contracts
            (list :accounts count :contracts (length contracts)
                  :storage-accounts storage-accounts :slots slots-total
                  :big-contracts big-contracts))))

(defun snap-density-rebase (state contracts count
                            &key (seed 2) (changed-per-mille 15))
  "Mutate a copy of STATE as a pivot rebase does, and return it.

CHANGED-PER-MILLE of the accounts change: an EOA's nonce and balance move, a
contract's balance moves and one of its storage slots is written.  That is the
shape of a half-hour pivot move on a public network: nearly the whole trie is
untouched and a scattered one to two percent of paths differ."
  (let* ((prng (make-snap-density-prng seed))
         (after (state-db-copy state))
         (contract-p (make-hash-table))
         (changed 0))
    (loop for index across contracts do (setf (gethash index contract-p) t))
    (dotimes (index count)
      (when (< (funcall prng 1000) changed-per-mille)
        (incf changed)
        (let ((address (snap-density-address index)))
          (state-db-set-account
           after address
           (make-state-account
            :nonce (+ 6000 (funcall prng 5000))
            :balance (+ 1 (funcall prng (ash 1 60)))))
          (when (gethash index contract-p)
            (state-db-set-storage
             after address (snap-density-slot index (1+ (funcall prng 8)))
             (+ 1 (funcall prng (ash 1 64))))))))
    (values after changed)))

;;; ------------------------------------------------------------------
;;; Account-trie structure and attribution
;;; ------------------------------------------------------------------

(defun snap-density-node-shape (encoded)
  "Return an account-trie node's hash children and, for a leaf, its value.

No account-trie node is ever inlined (docs/snap-account-closure.md, section
5), so every child reference is a 32-byte hash; an inline child here would
mean the fixture is not an account trie, and fails loudly."
  (let ((items (rlp-list-items (rlp-decode-one encoded :max-list-items 17))))
    (flet ((child (reference)
             (cond
               ((and (byte-vector-p reference) (= 32 (length reference)))
                (copy-seq reference))
               ((and (byte-vector-p reference) (zerop (length reference)))
                nil)
               (t (error "Account-trie node carries an inline child")))))
      (cond
        ((= 17 (length items))
         (values (loop for index below 16
                       for reference = (child (nth index items))
                       when reference collect reference)
                 nil))
        ((= 2 (length items))
         (let ((path (first items)))
           (if (logbitp 5 (aref path 0))
               (values '() (second items))
               (values (let ((reference (child (second items))))
                         (and reference (list reference)))
                       nil))))
        (t (error "Malformed account-trie node"))))))

(defun snap-density-trie (state)
  "Return STATE's account trie as a hash -> (children . leaf-value) table.

A freshly built trie is wholly dirty, so MPT-DIRTY-NODE-RECORDS enumerates
every node of that root and nothing else; the root check proves it."
  (let* ((trie (ethereum-lisp.state:state-db-state-trie state))
         (root (mpt-root-hash trie))
         (table (make-hash-table :test #'equalp)))
    (dolist (record (mpt-dirty-node-records trie))
      (multiple-value-bind (children value) (snap-density-node-shape (cdr record))
        (setf (gethash (car record) table) (cons children value))))
    (unless (nth-value 1 (gethash root table))
      (error "Account-trie enumeration does not contain its root"))
    (values table root)))

(defun snap-density-account-reason (value)
  "Name the external edge that can hold an account leaf open.

This is the same precedence SNAP-SYNC-CLOSED-ACCOUNT-PAGE-CONTENT counts with:
an account owning storage is charged to storage, any other open account to
code."
  (let ((account (decode-state-account-rlp value)))
    (if (hash32= (state-account-storage-root account) +empty-trie-hash+)
        :open-code
        :open-storage)))

(defun snap-density-classify (trie root present-p verdicts)
  "Attribute every account-trie node of TRIE to its storage outcome.

PRESENT-P answers whether a node hash is durable.  VERDICTS maps a leaf value
to :CLOSED or :OPEN as the closed writer's predicate last judged it at page
completion (closed wins: a leaf is open only if no page ever closed it).

A withheld node is charged to open storage when an open storage-owning leaf
lies beneath it, else to open code when an open code-only leaf does, else
to a leaf no page ever judged (a rebase changed it after its page was
downloaded under the older root), else to the page-boundary straddle -- a spine or range-straddling node whose subtree
is wholly closed but was never inside one delivered page.

Returns a plist: node totals, present, withheld by cause, and the walk a
healer with an account presence skip would make from ROOT (every absent node
fetched and descended, every present node reached from an absent parent
skipped)."
  (let ((open-memo (make-hash-table :test #'equalp))
        (present 0)
        (withheld-storage 0)
        (withheld-code 0)
        (withheld-straddle 0)
        (withheld-unjudged 0)
        (skip-fetched 0)
        (skip-skipped 0)
        (full-memo (make-hash-table :test #'equalp))
        (subtree-violations 0))
    (labels
        ((openness (hash)
           ;; Three flags: an open storage leaf below, an open code leaf below,
           ;; a leaf no page ever judged (a rebase changed it after its page
           ;; was downloaded under the older root).
           (multiple-value-bind (cached found) (gethash hash open-memo)
             (when found (return-from openness cached)))
           (destructuring-bind (children . value) (gethash hash trie)
             (let ((storage nil) (code nil) (unseen nil))
               (when value
                 (case (gethash value verdicts)
                   (:open
                    (if (eq :open-storage (snap-density-account-reason value))
                        (setf storage t)
                        (setf code t)))
                   ((nil) (setf unseen t))))
               (dolist (child children)
                 (destructuring-bind (s c u) (openness child)
                   (when s (setf storage t))
                   (when c (setf code t))
                   (when u (setf unseen t))))
               (setf (gethash hash open-memo) (list storage code unseen)))))
         (full-p (hash)
           ;; Present with every descendant present: the subtree half of I1.
           (multiple-value-bind (cached found) (gethash hash full-memo)
             (when found (return-from full-p cached)))
           (let ((children-full
                   (every #'identity
                          (mapcar #'full-p (car (gethash hash trie))))))
             (when (and (funcall present-p hash) (not children-full))
               (incf subtree-violations))
             (setf (gethash hash full-memo)
                   (and children-full (funcall present-p hash)))))
         (skip-walk (hash)
           (if (funcall present-p hash)
               (incf skip-skipped)
               (progn
                 (incf skip-fetched)
                 (dolist (child (car (gethash hash trie)))
                   (skip-walk child))))))
      (openness root)
      (full-p root)
      (maphash
       (lambda (hash shape)
         (declare (ignore shape))
         (if (funcall present-p hash)
             (incf present)
             (let ((flags (gethash hash open-memo)))
               (cond
                 ((first flags) (incf withheld-storage))
                 ((second flags) (incf withheld-code))
                 ((third flags) (incf withheld-unjudged))
                 (t (incf withheld-straddle))))))
       trie)
      (skip-walk root)
      (list :nodes (hash-table-count trie) :present present
            :withheld (- (hash-table-count trie) present)
            :withheld-open-storage withheld-storage
            :withheld-open-code withheld-code
            :withheld-straddle withheld-straddle
            :withheld-unjudged withheld-unjudged
            :skip-walk-processed (+ skip-fetched skip-skipped)
            :skip-walk-fetched skip-fetched
            :skip-walk-skipped skip-skipped
            :i1-subtree-violations subtree-violations))))

;;; ------------------------------------------------------------------
;;; One instrumented import
;;; ------------------------------------------------------------------

(defun call-with-snap-density-writer (closed-p depth thunk)
  "Run THUNK with the account writer selected by CLOSED-P and proofs at DEPTH.

Set process-globally, not bound: the multi-source importer prepares and
completes pages on worker threads, where a LET binding is invisible and the run
would silently exercise the legacy writer."
  (let ((writes ethereum-lisp.snap-sync::*snap-sync-account-closure-writes*)
        (lookup ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*)
        (coarse ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*)
        (nested
          ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*))
    (unwind-protect
         (progn
           (setf ethereum-lisp.snap-sync::*snap-sync-account-closure-writes*
                 closed-p
                 ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
                 depth
                 ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
                 depth
                 ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
                 (1+ depth))
           (funcall thunk))
      (setf ethereum-lisp.snap-sync::*snap-sync-account-closure-writes* writes
            ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
            lookup
            ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
            coarse
            ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
            nested))))

(defun snap-density-counting-source (backend counter)
  "A snap source over BACKEND that records each AccountRange page's size."
  (let ((base (snap-test-source backend)))
    (snap-test-source-with-account-callback
     base
     (lambda (request)
       (let ((response
               (funcall (ethereum-lisp.snap-sync:snap-sync-source-account-range
                         base)
                        request)))
         (funcall counter
                  (length (ethereum-lisp.snap::snap-account-range-accounts
                           response)))
         response)))))

(defun snap-density-arm
    (after after-root
     &key before before-root closed-p multi-p (byte-limit 25000) (depth 2)
          (rebase-after-pages 0) (seed 40))
  "Import AFTER-ROOT through a production importer and measure the account side.

With BEFORE, the range phase first runs REBASE-AFTER-PAGES pages under
BEFORE-ROOT, the progress is rebased to AFTER-ROOT, and the import then
finishes under AFTER-ROOT: the live mid-range rebase.  CLOSED-P selects the
closed account writer, MULTI-P the multi-source importer with two sources.
BYTE-LIMIT is both the AccountRange and the StorageRanges byte cap, which is
how the importer sends them.

The store the healer faces is sampled at SNAP-SYNC-HEAL-STATE entry, after the
range phase and the deferred-storage fill; the heal counters are the importer's
own last heal-progress event."
  (multiple-value-bind (trie root) (snap-density-trie after)
    (unless (bytes= root (hash32-bytes after-root))
      (error "Density fixture trie does not belong to its root"))
    (let* ((target (make-memory-key-value-database))
           (lock (sb-thread:make-mutex :name "snap-density"))
           (verdicts (make-hash-table :test #'equalp))
           (pages 0)
           (page-accounts 0)
           (heal-events '())
           (at-heal nil)
           (at-range-end nil)
           (counter
             (lambda (accounts)
               (sb-thread:with-mutex (lock)
                 (incf pages)
                 (incf page-accounts accounts))))
           (sources-for
             (lambda (state)
               (let ((backend
                       (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                        (make-memory-key-value-database) state)))
                 (if multi-p
                     (list (snap-density-counting-source backend counter)
                           (snap-density-counting-source backend counter))
                     (list (snap-density-counting-source backend counter))))))
           (snapshot
             (lambda ()
               (let ((present (make-hash-table :test #'equalp)))
                 (maphash (lambda (hash shape)
                            (declare (ignore shape))
                            (when (nth-value 1 (trie-node-store-get target hash))
                              (setf (gethash hash present) t)))
                          trie)
                 present)))
           (real-predicate
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-account-closure-predicate))
           (real-heal
             (fdefinition 'ethereum-lisp.snap-sync::snap-sync-heal-state))
           (real-make-work
             (fdefinition 'ethereum-lisp.snap-sync::snap-sync-make-heal-work))
           (real-proofs-present
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-filtered-healed-subtrees-present))
           (heal-account-reached (make-hash-table :test #'equalp))
           (heal-account-proof-skips (make-hash-table :test #'equalp))
           (real-fill
             (fdefinition
              'ethereum-lisp.snap-sync::snap-sync-fill-storage-then-heal))
           (pivot (lambda (offset) (make-hash32 (snap-test-hash (+ seed offset)))))
           (run-import
             (lambda (state state-root pivot-hash number max-pages)
               (if multi-p
                   (ethereum-lisp.snap-sync:snap-sync-import-state-multi
                    target (funcall sources-for state)
                    :pivot-hash pivot-hash :pivot-number number
                    :state-root state-root :target-hash pivot-hash
                    :chain-id 560048 :genesis-hash (funcall pivot 1)
                    :authority-id (funcall pivot 2) :byte-limit byte-limit
                    :max-pages max-pages
                    :on-heal-progress
                    (lambda (event)
                      (sb-thread:with-mutex (lock) (push event heal-events))))
                   (ethereum-lisp.snap-sync:snap-sync-import-state
                    target (first (funcall sources-for state))
                    :pivot-hash pivot-hash :pivot-number number
                    :state-root state-root :target-hash pivot-hash
                    :chain-id 560048 :genesis-hash (funcall pivot 1)
                    :authority-id (funcall pivot 2) :byte-limit byte-limit
                    :max-pages max-pages
                    :on-heal-progress
                    (lambda (event) (push event heal-events)))))))
      (call-with-snap-density-writer
       closed-p depth
       (lambda ()
         (unwind-protect
              (progn
                (setf
                 (fdefinition
                  'ethereum-lisp.snap-sync::snap-sync-account-closure-predicate)
                 (lambda (database leaf-values codes)
                   (let ((predicate
                           (funcall real-predicate database leaf-values codes)))
                     (lambda (value)
                       (let ((closed (funcall predicate value)))
                         (sb-thread:with-mutex (lock)
                           (if closed
                               (setf (gethash value verdicts) :closed)
                               (unless (eq :closed (gethash value verdicts))
                                 (setf (gethash value verdicts) :open))))
                         closed))))
                 (fdefinition 'ethereum-lisp.snap-sync::snap-sync-fill-storage-then-heal)
                 (lambda (&rest arguments)
                   (setf at-range-end (funcall snapshot))
                   (apply real-fill arguments))
                 (fdefinition 'ethereum-lisp.snap-sync::snap-sync-heal-state)
                 (lambda (&rest arguments)
                   (setf at-heal (funcall snapshot))
                   (apply real-heal arguments))
                 ;; The healer's counters mix account and storage nodes.  Every
                 ;; account node it reaches is created as a work item first, and
                 ;; every account subtree it skips on a closure proof is answered
                 ;; by the proof lookup, so these two seams split them out.
                 (fdefinition 'ethereum-lisp.snap-sync::snap-sync-make-heal-work)
                 (lambda (kind account-hash path reference &rest keys)
                   (when (and (eq kind :account)
                              (member (getf keys :marker-state)
                                      '(nil :armed :inside)))
                     (sb-thread:with-mutex (lock)
                       (setf (gethash reference heal-account-reached) t)))
                   (apply real-make-work kind account-hash path reference keys))
                 (fdefinition
                  'ethereum-lisp.snap-sync::snap-sync-filtered-healed-subtrees-present)
                 (lambda (database references kinds bloom)
                   (let ((present (funcall real-proofs-present
                                           database references kinds bloom)))
                     (sb-thread:with-mutex (lock)
                       (dotimes (index (length references))
                         (when (and (eq :account (aref kinds index))
                                    (= 1 (aref present index)))
                           (setf (gethash (aref references index)
                                          heal-account-proof-skips)
                                 t))))
                     present)))
                (when before
                  (funcall run-import before before-root (funcall pivot 3) 100
                           rebase-after-pages)
                  (ethereum-lisp.snap-sync:snap-sync-rebase-progress
                   target :pivot-hash (funcall pivot 4) :pivot-number 110
                   :state-root after-root :target-hash (funcall pivot 4)
                   :chain-id 560048 :genesis-hash (funcall pivot 1)
                   :authority-id (funcall pivot 2)))
                (let* ((final (funcall run-import after after-root
                                       (funcall pivot 4) 110 nil))
                       (last-event (first heal-events))
                       (faced (or at-heal at-range-end))
                       (shape
                         (and faced
                              (snap-density-classify
                               trie root
                               (lambda (hash) (nth-value 1 (gethash hash faced)))
                               verdicts))))
                  (append
                   (list
                    :completed-p
                    (ethereum-lisp.snap-sync:snap-sync-progress-completed-p final)
                    :installed-root
                    (nth-value 0 (kv-get-chain-record
                                  target :state-history
                                  (hash32-bytes (funcall pivot 4))))
                    :pages pages
                    :accounts-per-page (if (plusp pages)
                                           (round page-accounts pages)
                                           0)
                    :healer-ran-p (not (null at-heal))
                    :range-persisted
                    (and at-range-end (hash-table-count at-range-end))
                    :open-verdicts
                    (loop for verdict being the hash-values of verdicts
                          count (eq verdict :open))
                    :processed
                    (and last-event
                         (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
                          last-event))
                    :reused
                    (and last-event
                         (ethereum-lisp.snap-sync:snap-sync-heal-progress-reused-nodes
                          last-event))
                    :fetched
                    (and last-event
                         (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
                          last-event))
                    :skipped
                    (and last-event
                         (ethereum-lisp.snap-sync:snap-sync-heal-progress-skipped-subtrees
                          last-event))
                    :heal-account-reached (hash-table-count heal-account-reached)
                    :heal-account-proof-skips
                    (hash-table-count heal-account-proof-skips)
                    :heal-account-decoded
                    (- (hash-table-count heal-account-reached)
                       (hash-table-count heal-account-proof-skips))
                    :promoted
                    (and last-event
                         (ethereum-lisp.snap-sync:snap-sync-heal-progress-promoted-subtrees
                          last-event)))
                   shape)))
           (setf
            (fdefinition
             'ethereum-lisp.snap-sync::snap-sync-account-closure-predicate)
            real-predicate
            (fdefinition 'ethereum-lisp.snap-sync::snap-sync-fill-storage-then-heal)
            real-fill
            (fdefinition 'ethereum-lisp.snap-sync::snap-sync-heal-state)
            real-heal
            (fdefinition 'ethereum-lisp.snap-sync::snap-sync-make-heal-work)
            real-make-work
            (fdefinition
             'ethereum-lisp.snap-sync::snap-sync-filtered-healed-subtrees-present)
            real-proofs-present)))))))

;;; ------------------------------------------------------------------
;;; The pinned measurement
;;; ------------------------------------------------------------------

(defun snap-density-report (label plist)
  (format *standard-output* "~&; density ~A:~{ ~(~A~)=~A~}~%" label
          (loop for (key value) on plist by #'cddr
                unless (typep value 'vector) append (list key value))))

(deftest snap-closed-account-writer-at-page-density-and-after-a-mid-range-rebase
  (:layer :integration :module :p2p)
  ;; Two thousand accounts, fifteen percent of them contracts sharing a code
  ;; pool, most contracts owning one to eight slots and three owning over a
  ;; thousand, which the 30,000-byte StorageRanges cap chunks.  The same cap
  ;; makes AccountRange pages of about four hundred accounts through the
  ;; single-source importer, so interior nodes lie wholly inside pages as they
  ;; do live.  Closure proofs are published and consulted at depth one, the
  ;; geometry in which a depth bucket is wider than a page and the legacy
  ;; healer re-walks after a rebase (SNAP-MID-RANGE-REBASE-ZEROES-RANGE-PLAN-
  ;; PROMOTION).  docs/evidence/sec5-closure-density-measurement.txt holds the
  ;; 5,000-account tables, both depths and the multi-source arms.
  (multiple-value-bind (before contracts population) (snap-density-state 2000)
    (is (= 2000 (getf population :accounts)))
    (is (plusp (getf population :contracts)))
    (is (= 3 (getf population :big-contracts)))
    (let* ((before-root (state-db-root before))
           (closed (snap-density-arm before before-root
                                     :closed-p t :byte-limit 30000 :depth 1)))
      (snap-density-report "no-rebase closed" closed)
      (is (getf closed :completed-p))
      (is (bytes= (hash32-bytes before-root) (getf closed :installed-root)))
      ;; Production-like page density, not one account per task.
      (is (> (getf closed :accounts-per-page) 300))
      ;; I1 read back off the store the healer faced.
      (is (zerop (getf closed :i1-subtree-violations)))
      ;; The withheld fraction at page density: below one percent of the
      ;; account trie (measured 17 of 2,647).  Both causes the design names
      ;; must be visible, or the attribution is not measuring anything: the
      ;; three chunked contracts are the only open accounts, and the page
      ;; boundaries withhold the spine above them.
      (is (= 3 (getf closed :open-verdicts)))
      (is (plusp (getf closed :withheld-open-storage)))
      (is (plusp (getf closed :withheld-straddle)))
      (is (< (* 100 (getf closed :withheld)) (getf closed :nodes)))
      ;; Positive controls for the two store-reading counters: a store that
      ;; holds nothing withholds everything, and a store missing one leaf under
      ;; present ancestors is an I1 violation.
      (multiple-value-bind (trie root) (snap-density-trie before)
        (let ((empty (snap-density-classify
                      trie root (constantly nil) (make-hash-table))))
          (is (= (getf empty :nodes) (getf empty :withheld)))
          (is (>= (* 100 (getf empty :withheld)) (getf empty :nodes))))
        (let ((leaf (loop for hash being the hash-keys of trie
                            using (hash-value shape)
                          when (cdr shape) return hash)))
          (is leaf)
          (is (plusp
               (getf (snap-density-classify
                      trie root (lambda (hash) (not (bytes= hash leaf)))
                      (make-hash-table))
                     :i1-subtree-violations)))))
      ;; The live stall: the pivot moves after half the pages, 1.5% of the
      ;; accounts change, and the rest of the range downloads under the new
      ;; root.  Both arms install the same root; they differ only in the writer.
      (multiple-value-bind (after changed)
          (snap-density-rebase before contracts 2000)
        (is (plusp changed))
        (let* ((after-root (state-db-root after))
               (arms
                 (loop for closed-p in '(nil t)
                       collect (snap-density-arm
                                after after-root
                                :before before :before-root before-root
                                :closed-p closed-p :byte-limit 30000 :depth 1
                                :rebase-after-pages 2)))
               (legacy (first arms))
               (subject (second arms)))
          (snap-density-report "rebase legacy" legacy)
          (snap-density-report "rebase closed" subject)
          (dolist (arm arms)
            (is (getf arm :completed-p))
            (is (bytes= (hash32-bytes after-root) (getf arm :installed-root)))
            (is (getf arm :healer-ran-p)))
          (is (zerop (getf subject :i1-subtree-violations)))
          ;; The rebase is what the healer repairs: nodes no page judged.
          (is (plusp (getf subject :withheld-unjudged)))
          ;; Positive control: the legacy healer really re-walks after the
          ;; rebase -- it decodes many times the account nodes that changed.
          (is (> (getf legacy :heal-account-decoded)
                 (* 3 (getf subject :withheld-unjudged))))
          ;; The comparison the epoch bump rests on.  With an account presence
          ;; skip, the healer decodes only the absent nodes it fetches and
          ;; stops at every present one, so its walk over the closed store is
          ;; SKIP-WALK-*.  That skip is not in this tree yet; the walk is
          ;; computed from the store the healer faced and is an estimate of the
          ;; rule, not a measurement of it.  It is strictly below legacy both in
          ;; account nodes decoded and in account nodes touched at all.
          (is (< (getf subject :skip-walk-fetched)
                 (getf legacy :heal-account-decoded)))
          (is (< (getf subject :skip-walk-processed)
                 (getf legacy :heal-account-reached)))
          ;; DEFECT ASSERTION for the interim, not the target.  The healer in
          ;; this tree trusts an account node only through a closure proof at
          ;; its lookup depth, and after a rebase the depth-one nodes above
          ;; every changed path are new hashes, so on a closed-writer store it
          ;; re-walks MORE than legacy.  This is why the writer sits behind its
          ;; seam until the presence skip lands; that change must turn this
          ;; comparison around and retarget it.
          (is (> (getf subject :heal-account-decoded)
                 (getf legacy :heal-account-decoded))))))))
