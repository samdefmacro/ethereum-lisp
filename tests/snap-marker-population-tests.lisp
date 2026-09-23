(in-package #:ethereum-lisp.test)

;;;; Where the range phase's incomplete-node markers come from.
;;;;
;;;; On a fresh epoch-seven store the account-page writer marks nothing, yet a
;;;; live Hoodi run reached healing with ~340,000 present nodes carrying the
;;;; `snap-incomplete-trie-node-v1:' marker.  The healer processes every present
;;;; marked node, so that population is the healer's local walk.  This file
;;;; attributes every marker to the site that wrote it, counts what survives to
;;;; SNAP-SYNC-HEAL-STATE entry and to import completion, and judges each
;;;; survivor against the store: STALE when the node and its whole trie-node
;;;; closure are durable, GENUINE when something beneath it is absent.

(defvar *snap-marker-site* nil
  "The marker-writing site the current thread is inside, for attribution.")

(defun snap-marker-node-children (encoded)
  "Return the hash children of trie node ENCODED, descending inline children."
  (let ((children '()))
    (labels ((reference (item)
               (cond
                 ((rlp-list-p item) (node item))
                 ((and (byte-vector-p item) (= 32 (length item)))
                  (push (copy-seq item) children))
                 ((and (byte-vector-p item) (zerop (length item))) nil)
                 (t (error "Malformed trie-node child reference"))))
             (node (object)
               (let ((items (rlp-list-items object)))
                 (cond
                   ((= 17 (length items))
                    (loop for index below 16
                          do (reference (nth index items))))
                   ((= 2 (length items))
                    (let ((path (first items)))
                      (unless (logbitp 5 (aref path 0))
                        (reference (second items)))))
                   (t (error "Malformed trie node"))))))
      (node (rlp-decode-one encoded :max-list-items 17)))
    children))

(defun snap-marker-reachable (database root)
  "Return the set of node hashes reachable from ROOT in DATABASE's trie table.

Absent nodes are included (they are reachable by reference) and reported as the
second value, the number of reachable hashes the store does not hold."
  (let ((seen (make-hash-table :test #'equalp))
        (absent 0)
        (stack (list (copy-seq root))))
    (loop while stack
          do (let ((hash (pop stack)))
               (unless (nth-value 1 (gethash hash seen))
                 (setf (gethash hash seen) t)
                 (multiple-value-bind (encoded present-p)
                     (trie-node-store-get database hash)
                   (if present-p
                       (dolist (child (snap-marker-node-children encoded))
                         (push child stack))
                       (incf absent))))))
    (values seen absent)))

(defun snap-marker-closed-p (database hash memo)
  "True when HASH and every trie node beneath it are durable in DATABASE."
  (multiple-value-bind (cached found) (gethash hash memo)
    (when found (return-from snap-marker-closed-p cached)))
  (setf (gethash hash memo)
        (multiple-value-bind (encoded present-p)
            (trie-node-store-get database hash)
          (and present-p
               (every (lambda (child) (snap-marker-closed-p database child memo))
                      (snap-marker-node-children encoded))
               t))))

(defun snap-marker-markers (database)
  "Return the durable incomplete-node marker set of DATABASE."
  (ethereum-lisp.snap-sync::snap-sync-load-incomplete-nodes database))

(defun snap-marker-owners (database state-root)
  "Map every trie node reachable from STATE-ROOT to its owning trie.

Values are :ACCOUNT, or (:STORAGE . STORAGE-ROOT-BYTES).  Read off the store
after the import completed, so every node is present."
  (let ((owners (make-hash-table :test #'equalp))
        (storage-roots '()))
    (let ((accounts (snap-marker-reachable database (hash32-bytes state-root))))
      (maphash
       (lambda (hash ignored)
         (declare (ignore ignored))
         (setf (gethash hash owners) :account)
         (multiple-value-bind (encoded present-p)
             (trie-node-store-get database hash)
           (when present-p
             (let ((items (rlp-list-items
                           (rlp-decode-one encoded :max-list-items 17))))
               (when (and (= 2 (length items))
                          (logbitp 5 (aref (first items) 0)))
                 (let ((account (decode-state-account-rlp (second items))))
                   (unless (hash32= (state-account-storage-root account)
                                    +empty-trie-hash+)
                     (pushnew (hash32-bytes
                               (state-account-storage-root account))
                              storage-roots :test #'equalp))))))))
       accounts))
    (dolist (root storage-roots)
      (maphash (lambda (hash ignored)
                 (declare (ignore ignored))
                 (unless (gethash hash owners)
                   (setf (gethash hash owners) (cons :storage root))))
               (snap-marker-reachable database root)))
    owners))

(defun snap-marker-storage-class (database storage-root)
  "Classify one storage trie by the range path that delivered it.

:CURSOR-SET when a StorageRanges cursor set exists for this exact root (the
byte-capped path, single or multi source), else :NO-CURSOR-SET: answered by one
response, or a root a rebase moved to after its content arrived under another."
  (let* ((prefix ethereum-lisp.snap-sync::+snap-sync-storage-task-identifier-prefix+)
         (start (kv-chain-record-key :metadata prefix))
         (end (kv-chain-record-key
               :metadata
               (ethereum-lisp.snap-sync::snap-sync-byte-prefix-end prefix)))
         (found nil))
    (multiple-value-bind (iterator close) (kv-iterator database :start start :end end)
      (unwind-protect
           (loop
             (multiple-value-bind (key value present-p) (funcall iterator)
               (declare (ignore value))
               (unless present-p (return))
               (let ((identifier (kv-chain-record-key-identifier :metadata key)))
                 (when (bytes= storage-root
                               (subseq identifier (+ (length prefix) 32)
                                       (+ (length prefix) 64)))
                   (setf found t)
                   (return)))))
        (when close (funcall close))))
    (if found :cursor-set :no-cursor-set)))

(defun snap-marker-verdicts (database markers)
  "Judge every marker in MARKERS against DATABASE as it stands now."
  (let ((memo (make-hash-table :test #'equalp))
        (verdicts (make-hash-table :test #'equalp)))
    (maphash (lambda (hash ignored)
               (declare (ignore ignored))
               (setf (gethash hash verdicts)
                     (if (snap-marker-closed-p database hash memo)
                         :stale :genuine)))
             markers)
    verdicts))

(defun snap-marker-storage-root-proofs (database)
  "Return every storage root carrying a whole-root closure proof in DATABASE."
  (let* ((prefix
           ethereum-lisp.snap-sync::+snap-sync-healed-storage-root-identifier-prefix+)
         (start (kv-chain-record-key :metadata prefix))
         (end (kv-chain-record-key
               :metadata
               (ethereum-lisp.snap-sync::snap-sync-byte-prefix-end prefix)))
         (roots '()))
    (multiple-value-bind (iterator close) (kv-iterator database :start start :end end)
      (unwind-protect
           (loop
             (multiple-value-bind (key value present-p) (funcall iterator)
               (declare (ignore value))
               (unless present-p (return))
               (push (subseq (kv-chain-record-key-identifier :metadata key)
                             (length prefix))
                     roots)))
        (when close (funcall close))))
    roots))

(defun snap-marker-census (database verdicts owners creators)
  "Attribute judged markers by creating site and owning trie.

VERDICTS maps each marker to :STALE or :GENUINE as judged against the store the
healer faced, which SNAP-MARKER-VERDICTS takes at that moment."
  (let ((rows (make-hash-table :test #'equal))
        (classes (make-hash-table :test #'equalp)))
    (maphash
     (lambda (hash verdict)
       (let* ((owner (gethash hash owners))
              (trie (cond ((null owner) :unreachable)
                          ((eq owner :account) :account)
                          (t (or (gethash (cdr owner) classes)
                                 (setf (gethash (cdr owner) classes)
                                       (snap-marker-storage-class
                                        database (cdr owner)))))))
              (site (or (gethash hash creators) :unknown))
              (key (list site trie verdict)))
         (incf (gethash key rows 0))))
     verdicts)
    (sort (loop for key being the hash-keys of rows using (hash-value count)
                collect (append key (list count)))
          #'> :key #'fourth)))

(defun call-with-snap-marker-instrumentation (thunk)
  "Run THUNK with every marker put and delete attributed to its site.

Returns THUNK's value and a plist (:CREATORS table :CREATED alist :DELETED alist)."
  (let* ((lock (sb-thread:make-mutex :name "snap-marker"))
         (creators (make-hash-table :test #'equalp))
         (created (make-hash-table :test #'equal))
         (deleted (make-hash-table :test #'equal))
         (wrapped '()))
    (labels ((wrap (symbol function)
               (push (cons symbol (fdefinition symbol)) wrapped)
               (setf (fdefinition symbol) function))
             (site-wrapper (symbol site)
               (let ((real (fdefinition symbol)))
                 (wrap symbol
                       (lambda (&rest arguments)
                         (let ((*snap-marker-site*
                                 (if (functionp site)
                                     (funcall site arguments)
                                     site)))
                           (apply real arguments)))))))
      (unwind-protect
           (progn
             (site-wrapper
              'ethereum-lisp.snap-sync::snap-sync-populate-verified-storage-group
              (lambda (arguments)
                (if (ethereum-lisp.snap-sync::snap-sync-verified-storage-group-partial-p
                     (fourth arguments))
                    :storage-first-page
                    :storage-whole-group)))
             (site-wrapper
              'ethereum-lisp.snap-sync::snap-sync-build-storage-page-batch
              :storage-partition-page)
             (site-wrapper
              'ethereum-lisp.snap-sync::snap-sync-prepare-account-page-range
              :account-prebuffer)
             (site-wrapper
              'ethereum-lisp.snap-sync::snap-sync-buffer-account-page-content
              :account-page)
             (site-wrapper 'ethereum-lisp.snap-sync::%snap-sync-heal-state :healer)
             (site-wrapper
              'ethereum-lisp.snap-sync::snap-sync-publish-storage-root-closure
              :storage-root-closure)
             (let ((put (fdefinition
                         'ethereum-lisp.snap-sync::snap-sync-populate-incomplete-node-batch))
                   (delete (fdefinition
                            'ethereum-lisp.snap-sync::snap-sync-delete-incomplete-node-batch)))
               (wrap 'ethereum-lisp.snap-sync::snap-sync-populate-incomplete-node-batch
                     (lambda (batch reference)
                       (sb-thread:with-mutex (lock)
                         (let ((site (or *snap-marker-site* :other)))
                           (incf (gethash site created 0))
                           (setf (gethash (copy-seq reference) creators) site)))
                       (funcall put batch reference)))
               (wrap 'ethereum-lisp.snap-sync::snap-sync-delete-incomplete-node-batch
                     (lambda (batch reference)
                       (sb-thread:with-mutex (lock)
                         (incf (gethash (or *snap-marker-site* :other) deleted 0)))
                       (funcall delete batch reference))))
             (values (funcall thunk)
                     (list :creators creators
                           :created (alexandria:hash-table-alist created)
                           :deleted (alexandria:hash-table-alist deleted))))
        (loop for (symbol . function) in wrapped
              do (setf (fdefinition symbol) function))))))

(defun snap-marker-population-state
    (&key (accounts 300) (small-every 5) (big-contracts 2) (big-slots 3000))
  "Return a state with small single-response storage tries and BIG-CONTRACTS
byte-capped ones, plus a rebased copy that moves one big contract's storage
root and a handful of small accounts.  Values: before, after."
  (let ((state (make-state-db)))
    (dotimes (index accounts)
      (let ((address (snap-density-address index)))
        (state-db-set-account
         state address
         (make-state-account :nonce (1+ index) :balance (+ 1000 index)))
        (when (zerop (mod index small-every))
          (state-db-set-code state address (snap-density-code (mod index 7)))
          (loop for slot from 1 to (1+ (mod index 6))
                do (state-db-set-storage
                    state address (snap-density-slot index slot)
                    (+ 5000 slot))))))
    (dotimes (big big-contracts)
      (let* ((index (+ accounts big))
             (address (snap-density-address index)))
        (state-db-set-account
         state address (make-state-account :nonce 1 :balance 1))
        (state-db-set-code state address (snap-density-code (+ 100 big)))
        (loop for slot from 1 to big-slots
              do (state-db-set-storage
                  state address (snap-density-slot index slot)
                  (+ 70000 slot)))))
    (let ((after (state-db-copy state)))
      (dolist (index '(7 91 173 251))
        (state-db-set-account
         after (snap-density-address index)
         (make-state-account :nonce 9999 :balance (+ 424242 index))))
      ;; One slot of the first big contract changes, so its storage root does.
      (state-db-set-storage after (snap-density-address accounts)
                            (snap-density-slot accounts 17) 424242)
      (values state after))))

(defun snap-marker-population-arm
    (state state-root &key multi-p before before-root (rebase-after-pages 0)
                           (byte-limit 30000) (seed 70) (publish-p t))
  "Import STATE-ROOT into a fresh epoch-seven store and take the marker census.

With BEFORE, REBASE-AFTER-PAGES account pages are first downloaded under
BEFORE-ROOT and the progress is rebased: the live mid-range rebase.  PUBLISH-P
NIL disables SNAP-SYNC-PUBLISH-STORAGE-ROOT-CLOSURE, which is the store the
range phase produced before it existed.

At SNAP-SYNC-HEAL-STATE entry the arm also audits every whole-root storage
proof in the store: :ROOT-PROOFS counts them and :UNCLOSED-ROOT-PROOFS counts
those whose trie is not wholly durable there, which must be zero."
  (let* ((target (make-memory-key-value-database))
         (at-heal nil)
         (root-proofs nil)
         (unclosed-root-proofs nil)
         (heal-events '())
         (real-publish
           (fdefinition
            'ethereum-lisp.snap-sync::snap-sync-publish-storage-root-closure))
         (pivot (lambda (offset) (make-hash32 (snap-test-hash (+ seed offset)))))
         (sources-for
           (lambda (state)
             (let ((backend
                     (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                      (make-memory-key-value-database) state)))
               (if multi-p
                   (list (snap-test-source backend) (snap-test-source backend))
                   (list (snap-test-source backend))))))
         (run-import
           (lambda (state root pivot-hash number max-pages)
             (if multi-p
                 (ethereum-lisp.snap-sync:snap-sync-import-state-multi
                  target (funcall sources-for state)
                  :pivot-hash pivot-hash :pivot-number number
                  :state-root root :target-hash pivot-hash
                  :chain-id 560048 :genesis-hash (funcall pivot 1)
                  :authority-id (funcall pivot 2) :byte-limit byte-limit
                  :max-pages max-pages
                  :on-heal-progress
                  (lambda (event) (push event heal-events)))
                 (ethereum-lisp.snap-sync:snap-sync-import-state
                  target (first (funcall sources-for state))
                  :pivot-hash pivot-hash :pivot-number number
                  :state-root root :target-hash pivot-hash
                  :chain-id 560048 :genesis-hash (funcall pivot 1)
                  :authority-id (funcall pivot 2) :byte-limit byte-limit
                  :max-pages max-pages
                  :on-heal-progress
                  (lambda (event) (push event heal-events))))))
         (real-heal (fdefinition 'ethereum-lisp.snap-sync::snap-sync-heal-state)))
    (multiple-value-bind (final instrumentation)
        (call-with-snap-marker-instrumentation
         (lambda ()
           (unwind-protect
                (progn
                  (unless publish-p
                    (setf (fdefinition
                           'ethereum-lisp.snap-sync::snap-sync-publish-storage-root-closure)
                          (lambda (&rest arguments)
                            (declare (ignore arguments))
                            :disabled)))
                  (setf (fdefinition 'ethereum-lisp.snap-sync::snap-sync-heal-state)
                        (lambda (&rest arguments)
                          (unless at-heal
                            (setf at-heal (snap-marker-verdicts
                                           target (snap-marker-markers target)))
                            (let ((proofs (snap-marker-storage-root-proofs target))
                                  (memo (make-hash-table :test #'equalp)))
                              (setf root-proofs (length proofs)
                                    unclosed-root-proofs
                                    (count-if-not
                                     (lambda (root)
                                       (snap-marker-closed-p target root memo))
                                     proofs))))
                          (apply real-heal arguments)))
                  (when before
                    (funcall run-import before before-root (funcall pivot 3) 100
                             rebase-after-pages)
                    (ethereum-lisp.snap-sync:snap-sync-rebase-progress
                     target :pivot-hash (funcall pivot 4) :pivot-number 110
                     :state-root state-root :target-hash (funcall pivot 4)
                     :chain-id 560048 :genesis-hash (funcall pivot 1)
                     :authority-id (funcall pivot 2)))
                  (funcall run-import state state-root (funcall pivot 4) 110 nil))
             (setf (fdefinition 'ethereum-lisp.snap-sync::snap-sync-heal-state)
                   real-heal
                   (fdefinition
                    'ethereum-lisp.snap-sync::snap-sync-publish-storage-root-closure)
                   real-publish))))
      (let* ((owners (snap-marker-owners target state-root))
             (creators (getf instrumentation :creators))
             (at-end (snap-marker-verdicts target (snap-marker-markers target))))
        (list :closed-writes-p
              (ethereum-lisp.snap-sync::snap-sync-closed-account-writes-p target)
              :completed-p
              (ethereum-lisp.snap-sync:snap-sync-progress-completed-p final)
              :installed-root
              (nth-value 0 (kv-get-chain-record
                            target :state-history
                            (hash32-bytes (funcall pivot 4))))
              :created (getf instrumentation :created)
              :deleted (getf instrumentation :deleted)
              :root-proofs root-proofs
              :unclosed-root-proofs unclosed-root-proofs
              ;; Heal counters restart with each healer session, so report the
              ;; largest each reached rather than the last event.
              :processed
              (loop for event in heal-events
                    maximize
                    (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
                     event))
              :fetched
              (loop for event in heal-events
                    maximize
                    (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
                     event))
              :healer-marked-walk
              (or (cdr (assoc :healer (getf instrumentation :deleted))) 0)
              :at-heal-count (and at-heal (hash-table-count at-heal))
              :at-heal (and at-heal
                            (snap-marker-census target at-heal owners creators))
              :at-end-count (hash-table-count at-end)
              :at-end (snap-marker-census target at-end owners creators)
              :target target)))))

;;; ------------------------------------------------------------------
;;; The partitioned storage closure, measured and refused
;;; ------------------------------------------------------------------

(defun snap-marker-partitioned-store (state address byte-limit)
  "Fill ADDRESS's storage trie from STATE into a fresh epoch-seven store.

Only the StorageRanges partitions run -- %SNAP-SYNC-FILL-STORAGE-ROOT-RANGES,
not the publishing wrapper -- so the store is what the range phase leaves
before the closure step.  Values: the store, the account hash, the storage
root and the state root."
  (let* ((root (state-db-root state))
         (account-hash (keccak-256 (address-bytes address)))
         (storage-root (state-db-get-storage-root state address))
         (target (make-memory-key-value-database))
         (source
           (snap-test-source
            (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
             (make-memory-key-value-database) state))))
    (is (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p target))
    (is (ethereum-lisp.snap-sync::%snap-sync-fill-storage-root-ranges
         target (list source) root account-hash storage-root byte-limit))
    (values target account-hash storage-root root)))

(defun snap-marker-put-task-set (database state-root account-hash storage-root tasks)
  (let ((batch (make-kv-write-batch)))
    (ethereum-lisp.snap-sync::snap-sync-populate-storage-task-set-batch
     batch state-root account-hash storage-root tasks)
    (kv-apply-batch database batch)))

(defun snap-marker-task-set (database state-root account-hash storage-root)
  (multiple-value-bind (records present)
      (kv-get-chain-records
       database :metadata
       (coerce
        (loop for index below ethereum-lisp.snap-sync::+snap-sync-storage-task-count+
              collect (ethereum-lisp.snap-sync::snap-sync-storage-task-identifier
                       state-root account-hash storage-root index))
        'vector))
    (is (every (lambda (bit) (= 1 bit)) present))
    (loop for record across records
          collect (ethereum-lisp.snap-sync::snap-sync-storage-task-from-record
                   record))))

(deftest snap-storage-root-closure-refuses-without-full-coverage-under-one-root
  (:layer :unit :module :p2p)
  ;; A byte-capped contract's partitions leave every node above the four-nibble
  ;; proof depth marked incomplete, and nothing on the range path ever clears
  ;; those markers (docs/evidence/sec5-marker-population.txt).  The closure
  ;; step publishes the whole-root proof and clears them only when completeness
  ;; is provable: all sixteen cursors completed, tiling the keyspace, and a walk
  ;; from THIS root reaching only present nodes down to range-derived :STORAGE
  ;; proofs.  Each refusal below must publish nothing and delete nothing.
  (let* ((state (make-state-db))
         (address (snap-density-address 1))
         (other (snap-density-address 2)))
    (state-db-set-account state address (make-state-account :nonce 1 :balance 1))
    (loop for slot from 1 to 600
          do (state-db-set-storage state address (snap-density-slot 1 slot)
                                   (+ 70000 slot)))
    (state-db-set-account state other (make-state-account :nonce 2 :balance 2))
    (multiple-value-bind (target account-hash storage-root state-root)
        (snap-marker-partitioned-store state address 4000)
      (let* ((markers-before (hash-table-count (snap-marker-markers target)))
             (tasks (snap-marker-task-set target state-root account-hash
                                          storage-root))
             (root-bytes (hash32-bytes storage-root)))
        (flet ((publish (&optional (root storage-root))
                 (ethereum-lisp.snap-sync::snap-sync-publish-storage-root-closure
                  target state-root account-hash root))
               (untouched-p (&optional (root storage-root))
                 (and (= markers-before
                         (hash-table-count (snap-marker-markers target)))
                      (not (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
                            target (hash32-bytes root) :storage-root)))))
          ;; The shape the live store has: the chunked trie is complete on disk
          ;; and still marked.
          (is (plusp markers-before))
          (is (snap-marker-closed-p target root-bytes
                                    (make-hash-table :test #'equalp)))
          (is (untouched-p))
          ;; RED, coverage gap: task 0 claims to start one hash above zero, so
          ;; key 0 is owned by no completed cursor.  Completed flags alone
          ;; would pass.
          (let ((first (first tasks)))
            (snap-marker-put-task-set
             target state-root account-hash storage-root
             (cons (ethereum-lisp.snap-sync::snap-sync-account-task
                    :start (ethereum-lisp.snap-sync::snap-sync-integer-to-hash-bytes 1)
                    :limit (ethereum-lisp.snap-sync::snap-sync-account-task-limit first)
                    :completed-p t)
                   (rest tasks)))
            (is (eq :cursors-open (publish)))
            (is (untouched-p)))
          ;; RED, an open cursor: the same set with one partition unfinished.
          (let ((first (first tasks)))
            (snap-marker-put-task-set
             target state-root account-hash storage-root
             (cons (ethereum-lisp.snap-sync::snap-sync-account-task
                    :start (ethereum-lisp.snap-sync::snap-sync-account-task-start first)
                    :limit (ethereum-lisp.snap-sync::snap-sync-account-task-limit first)
                    :next-origin
                    (ethereum-lisp.snap-sync::snap-sync-account-task-start first))
                   (rest tasks)))
            (is (eq :cursors-open (publish)))
            (is (untouched-p)))
          (snap-marker-put-task-set target state-root account-hash storage-root tasks)
          ;; RED, a partition whose content never became durable: every cursor
          ;; says done, but one node the walk must reach is absent.
          (let* ((visited
                   (ethereum-lisp.snap-sync::snap-sync-storage-root-closure-walk
                    target storage-root))
                 (victim (car (last visited))))
            (is (> (length visited) 1))
            (multiple-value-bind (encoded present-p)
                (trie-node-store-get target victim)
              (is present-p)
              (let ((batch (make-kv-write-batch)))
                (kv-batch-delete-chain-record batch :trie-node victim)
                (kv-apply-batch target batch))
              (is (eq :missing-node (publish)))
              (is (untouched-p))
              (let ((batch (make-kv-write-batch)))
                (kv-batch-put-chain-record batch :trie-node victim encoded)
                (kv-apply-batch target batch))))
          ;; RED, partitions proved against a different root: a rebase moved
          ;; the contract to ROOT-2 (one slot differs) and its cursor set was
          ;; carried over completed.  Every page on disk was proved against
          ;; STORAGE-ROOT, so the walk from ROOT-2 meets the changed path and
          ;; refuses; the shared nodes' markers stay.
          (let ((moved (state-db-copy state)))
            (state-db-set-storage moved address (snap-density-slot 1 17) 424242)
            (let ((root-2 (state-db-get-storage-root moved address)))
              (is (not (hash32= root-2 storage-root)))
              (snap-marker-put-task-set target state-root account-hash root-2 tasks)
              (is (eq :missing-node (publish root-2)))
              (is (untouched-p root-2))
              (is (untouched-p))))
          ;; A legacy store keeps its behaviour.
          (let ((legacy (make-memory-key-value-database)))
            (snap-test-seed-legacy-trie-store legacy)
            (is (eq :legacy-store
                    (ethereum-lisp.snap-sync::snap-sync-publish-storage-root-closure
                     legacy state-root account-hash storage-root))))
          ;; Subject: the untouched set publishes, clears every marker this
          ;; trie carried, and is idempotent.
          (is (eq :closed (publish)))
          (is (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
               target root-bytes :storage-root))
          (is (zerop (hash-table-count (snap-marker-markers target))))
          (is (eq :already-closed (publish)))
          ;; Positive control for the closure oracle the integration arms use
          ;; to audit every published proof: a missing node makes it false.
          (let ((victim (first (snap-marker-node-children
                                (trie-node-store-get target root-bytes)))))
            (let ((batch (make-kv-write-batch)))
              (kv-batch-delete-chain-record batch :trie-node victim)
              (kv-apply-batch target batch))
            (is (not (snap-marker-closed-p target root-bytes
                                           (make-hash-table :test #'equalp))))))))))

(deftest snap-partitioned-storage-closure-leaves-the-healer-no-stale-marker
  (:layer :integration :module :p2p)
  ;; The live store: 372,561 marked nodes at heal entry against 28,665 fetched,
  ;; on an epoch-seven store whose account pages mark nothing.  Two byte-capped
  ;; contracts of 2,500 slots among 300 accounts reproduce it: every surviving
  ;; marker was written by a StorageRanges partition (the first byte-capped
  ;; page or a later cursor page) of a chunked trie, and every one is stale --
  ;; the node and its whole trie closure are durable before healing starts.
  (multiple-value-bind (before after)
      (snap-marker-population-state :big-slots 2500)
    (let* ((before-root (state-db-root before))
           (after-root (state-db-root after))
           (red (snap-marker-population-arm before before-root :publish-p nil))
           (single (snap-marker-population-arm before before-root))
           (multi (snap-marker-population-arm before before-root :multi-p t))
           (red-rebase
             (snap-marker-population-arm
              after after-root :before before :before-root before-root
              :rebase-after-pages 3 :byte-limit 8000 :publish-p nil))
           (rebase
             (snap-marker-population-arm
              after after-root :before before :before-root before-root
              :rebase-after-pages 3 :byte-limit 8000)))
      (dolist (entry (list (list "red" red) (list "single" single)
                           (list "multi" multi) (list "red-rebase" red-rebase)
                           (list "rebase" rebase)))
        (destructuring-bind (label arm) entry
          (let ((*print-pretty* nil))
            (format *standard-output*
                    "~&; marker population ~A: at-heal=~A healer-marked-walk=~A ~
processed=~A fetched=~A root-proofs=~A created=~S deleted=~S census=~S~%"
                    label (getf arm :at-heal-count)
                    (getf arm :healer-marked-walk) (getf arm :processed)
                    (getf arm :fetched) (getf arm :root-proofs)
                    (getf arm :created) (getf arm :deleted)
                    (getf arm :at-heal)))
          (is (getf arm :closed-writes-p))
          (is (getf arm :completed-p))
          (is (zerop (getf arm :at-end-count)))
          ;; No published whole-root proof may name a trie with an absent node
          ;; at heal entry (the oracle's own RED is in the unit test above).
          (is (zerop (getf arm :unclosed-root-proofs)))))
      (dolist (arm (list red single multi))
        (is (bytes= (hash32-bytes before-root)
                    (getf arm :installed-root))))
      ;; RED: the range phase as it stood.  Every marker at heal entry is a
      ;; stale partition marker of a chunked trie; none is genuine.
      (dolist (arm (list red red-rebase))
        (is (> (getf arm :at-heal-count) 1000))
        (dolist (row (getf arm :at-heal))
          (destructuring-bind (site trie verdict count) row
            (declare (ignore count))
            (is (member site '(:storage-first-page :storage-partition-page)))
            (is (not (eq trie :account)))
            (is (eq verdict :stale)))))
      ;; Subject: the genuinely open set at heal entry is empty, so the marked
      ;; population drops to it on every path, including after a mid-range
      ;; rebase, and the closure step deleted exactly what RED left behind.
      (dolist (arm (list single multi rebase))
        (is (zerop (getf arm :at-heal-count)))
        (is (>= (getf arm :root-proofs) 2)))
      (is (= (getf red :at-heal-count)
             (cdr (assoc :storage-root-closure (getf single :deleted)))))
      ;; And the healer's walk shrinks with it: the marked nodes it had to
      ;; process and complete, and the nodes it decoded at all.
      (dolist (pair (list (cons single red) (cons rebase red-rebase)))
        (is (> (getf (cdr pair) :healer-marked-walk) 1000))
        (is (< (* 10 (getf (car pair) :healer-marked-walk))
               (getf (cdr pair) :healer-marked-walk)))
        (is (< (getf (car pair) :processed) (getf (cdr pair) :processed)))))))

(deftest snap-storage-root-closure-publishes-a-trie-wider-than-one-multi-get
  (:layer :unit :module :p2p)
  ;; Hoodi, revision cceee42f, 2026-09-22T23:19Z: every page carrying a chunked
  ;; contract wider than +KV-GET-MANY-MAX-KEYS+ trie nodes failed with "KV
  ;; multi-get exceeds 4096 keys" and the range phase stopped at its ninth
  ;; page.  The closure step looked up the incomplete markers of every walked
  ;; node in ONE native multi-get, while the walk itself admits up to
  ;; *SNAP-SYNC-STORAGE-ROOT-CLOSURE-MAX-NODES*.  RED on that code: PUBLISH
  ;; signals the multi-get bound.  Subject: the lookup goes in bounded groups,
  ;; the proof is published and every marker of the walked trie is cleared.
  ;;
  ;; The storage trie is built with the bare MPT API and written straight into
  ;; the store: a state-db with this many slots on one account, and the
  ;; partition import helper, both exhaust the warm image's heap.  The shape
  ;; the closure step sees is the live one: an epoch-seven store, every node
  ;; present and marked, sixteen completed cursors tiling the keyspace, and no
  ;; :STORAGE proof to stop the walk.
  (let* ((trie (make-mpt))
         (target (make-memory-key-value-database))
         (state-root (make-hash32 (keccak-256 (rlp-encode "state root"))))
         (account-hash (keccak-256 (address-bytes (snap-density-address 1)))))
    (loop for slot from 1 to 5000
          do (ethereum-lisp.trie::mpt-put
              trie
              (keccak-256 (hash32-bytes (snap-density-slot 1 slot)))
              (rlp-encode (+ 90000 slot))))
    ;; The epoch is stamped only on an empty store, so before the trie lands.
    (is (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p target))
    (let* ((storage-root (ethereum-lisp.trie::mpt-persist target trie))
           (root-bytes (hash32-bytes storage-root)))
      (multiple-value-bind (reachable absent) (snap-marker-reachable target root-bytes)
        (is (zerop absent))
        ;; Wider than one multi-get, or the test cannot go red.
        (is (> (hash-table-count reachable)
               ethereum-lisp.database:+kv-get-many-max-keys+))
        (let ((batch (make-kv-write-batch)))
          (loop for hash being the hash-keys of reachable
                do (ethereum-lisp.snap-sync::snap-sync-populate-incomplete-node-batch
                    batch hash))
          (kv-apply-batch target batch))
        (is (= (hash-table-count reachable)
               (hash-table-count (snap-marker-markers target)))))
      (snap-marker-put-task-set
       target state-root account-hash storage-root
       (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
        :count ethereum-lisp.snap-sync::+snap-sync-storage-task-count+
        :completed-p t))
      (is (eq :closed
              (ethereum-lisp.snap-sync::snap-sync-publish-storage-root-closure
               target state-root account-hash storage-root)))
      (is (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
           target root-bytes :storage-root))
      (is (zerop (hash-table-count (snap-marker-markers target)))))))

;;; ------------------------------------------------------------------
;;; The closure walk's read cost
;;; ------------------------------------------------------------------

(defvar *snap-closure-read-inside-multi-get* nil
  "True inside a counted multi-get, whose generic fallback calls KV-GET.")

(defclass snap-closure-read-counting-database (memory-key-value-database)
  ((point-gets :initform (make-hash-table)
               :accessor snap-closure-read-point-gets)
   (multi-gets :initform (make-hash-table)
               :accessor snap-closure-read-multi-gets)
   (trie-node-keys :initform (make-hash-table :test #'equalp)
                   :accessor snap-closure-read-trie-node-keys)
   (calls :initform '() :accessor snap-closure-read-calls))
  (:documentation
   "A memory store counting point reads and native multi-gets by record kind.

Every multi-get of the closure walk names one kind, so a call is attributed to
its first key's.  CALLS keeps (KIND . KEY-COUNT) per multi-get, newest first;
TRIE-NODE-KEYS every :TRIE-NODE key read by either path."))

(defun snap-closure-read-kind (key)
  (ethereum-lisp.database::kv-chain-record-key-kind key))

(defun snap-closure-read-note-trie-node (database key)
  (when (eq :trie-node (snap-closure-read-kind key))
    (setf (gethash (copy-seq key) (snap-closure-read-trie-node-keys database))
          t)))

(defmethod kv-get :around
    ((database snap-closure-read-counting-database) key &optional default)
  (declare (ignore default))
  (unless *snap-closure-read-inside-multi-get*
    (incf (gethash (snap-closure-read-kind key)
                   (snap-closure-read-point-gets database) 0))
    (snap-closure-read-note-trie-node database key))
  (call-next-method))

(defmethod kv-get-many :around
    ((database snap-closure-read-counting-database) keys &optional default)
  (declare (ignore default))
  (when (plusp (length keys))
    (let ((kind (snap-closure-read-kind (elt keys 0))))
      (incf (gethash kind (snap-closure-read-multi-gets database) 0))
      (push (cons kind (length keys)) (snap-closure-read-calls database))
      (map nil (lambda (key) (snap-closure-read-note-trie-node database key))
           keys)))
  (let ((*snap-closure-read-inside-multi-get* t))
    (call-next-method)))

(defun snap-closure-read-reset (database)
  (clrhash (snap-closure-read-point-gets database))
  (clrhash (snap-closure-read-multi-gets database))
  (clrhash (snap-closure-read-trie-node-keys database))
  (setf (snap-closure-read-calls database) '()))

(defun snap-closure-read-count (database table kind)
  (gethash kind (funcall table database) 0))

(defun snap-closure-reference-walk (database storage-root)
  "The depth-first closure walk as it stood at 8933d407: one point read of the
:STORAGE proof and one of the node for every node visited.  Kept as the read
count and visited set the level walk is judged against."
  (let ((seen (make-hash-table :test #'equalp))
        (visited '())
        (stack (list (hash32-bytes storage-root))))
    (flet ((refuse (reason)
             (return-from snap-closure-reference-walk (values nil reason))))
      (loop while stack
            do (let ((hash (pop stack)))
                 (unless (or (nth-value 1 (gethash hash seen))
                             (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
                              database hash :storage))
                   (setf (gethash hash seen) t)
                   (multiple-value-bind (encoded present-p)
                       (trie-node-store-get database hash)
                     (unless present-p (refuse :missing-node))
                     (unless (bytes= hash (keccak-256 encoded))
                       (refuse :invalid-node))
                     (push hash visited)
                     (let ((items (rlp-list-items
                                   (rlp-decode-one encoded :max-list-items 17))))
                       (flet ((reference (item)
                                (when (and (byte-vector-p item)
                                           (= 32 (length item)))
                                  (push (copy-seq item) stack))))
                         (case (length items)
                           (17 (loop for index below 16
                                     do (reference (nth index items))))
                           (2 (unless (logbitp 5 (aref (first items) 0))
                                (reference (second items))))
                           (otherwise (refuse :invalid-node))))))))))
    (values (nreverse visited) :closed)))

(defun snap-closure-read-wide-store (slots)
  "An epoch-seven counting store holding one SLOTS-wide storage trie, every
node marked, sixteen completed cursors, and one :STORAGE proof on the root's
first hash child.  Values: the store, the storage root, the proved child, the
state root and the account hash."
  (let ((trie (make-mpt))
        (target (make-instance 'snap-closure-read-counting-database))
        (state-root (make-hash32 (keccak-256 (rlp-encode "state root"))))
        (account-hash (keccak-256 (address-bytes (snap-density-address 1)))))
    (loop for slot from 1 to slots
          do (ethereum-lisp.trie::mpt-put
              trie
              (keccak-256 (hash32-bytes (snap-density-slot 1 slot)))
              (rlp-encode (+ 90000 slot))))
    (is (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p target))
    (let* ((storage-root (ethereum-lisp.trie::mpt-persist target trie))
           (root-bytes (hash32-bytes storage-root))
           (proved (first (snap-marker-node-children
                           (trie-node-store-get target root-bytes)))))
      (let ((batch (make-kv-write-batch)))
        (loop for hash being the hash-keys
                of (snap-marker-reachable target root-bytes)
              do (ethereum-lisp.snap-sync::snap-sync-populate-incomplete-node-batch
                  batch hash))
        (ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch
         batch proved :storage)
        (kv-apply-batch target batch))
      (snap-marker-put-task-set
       target state-root account-hash storage-root
       (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
        :count ethereum-lisp.snap-sync::+snap-sync-storage-task-count+
        :completed-p t))
      (values target storage-root proved state-root account-hash))))

(deftest snap-storage-root-closure-walk-reads-a-level-per-multi-get
  (:layer :unit :module :p2p)
  ;; Hoodi, revision aac5f762: the closure step made every account page that
  ;; carried a chunked contract spend 90,000-142,000 ms in storage (448 ms on
  ;; the revision before it), because the walk issued one point read for each
  ;; node's :STORAGE proof and one for the node itself, on a ~45 GB RocksDB
  ;; store and on the page's own thread.  RED (the walk at 8933d407, kept here
  ;; as SNAP-CLOSURE-REFERENCE-WALK and loaded into the image as the shipped
  ;; walk): 2N point reads and no multi-get.  Subject: no point read, and per
  ;; kind at most ceil(N / 4096) + levels multi-gets, visiting the same set and
  ;; deleting the same markers; the one :STORAGE proof still stops the descent.
  (multiple-value-bind (target storage-root proved state-root account-hash)
      (snap-closure-read-wide-store 5000)
    (let* ((root-bytes (hash32-bytes storage-root))
           (reachable (snap-marker-reachable target root-bytes))
           (below-proof (snap-marker-reachable target proved)))
      (snap-closure-read-reset target)
      (multiple-value-bind (reference reference-reason)
          (snap-closure-reference-walk target storage-root)
        (is (eq :closed reference-reason))
        (let ((n (length reference)))
          ;; Wide enough to need several node multi-gets, and the proof cut a
          ;; real subtree out of the walk.
          (is (> n ethereum-lisp.database:+kv-get-many-max-keys+))
          (is (> (hash-table-count below-proof) 1))
          (is (= n (- (hash-table-count reachable)
                      (hash-table-count below-proof))))
          ;; The RED shape: a point read per node, and one per proof probe.
          (is (= n (snap-closure-read-count
                    target #'snap-closure-read-point-gets :trie-node)))
          (is (= (1+ n) (snap-closure-read-count
                         target #'snap-closure-read-point-gets :metadata)))
          (is (zerop (hash-table-count (snap-closure-read-multi-gets target))))
          (snap-closure-read-reset target)
          (multiple-value-bind (visited reason calls levels nodes)
              (ethereum-lisp.snap-sync::snap-sync-storage-root-closure-walk
               target storage-root)
            ;; RED at 8933d407: 2N + 1 point reads here.
            (is (zerop (hash-table-count (snap-closure-read-point-gets target))))
            (let ((bound (+ (ceiling n ethereum-lisp.database:+kv-get-many-max-keys+)
                            levels))
                  (node-gets (snap-closure-read-count
                              target #'snap-closure-read-multi-gets :trie-node))
                  (proof-gets (snap-closure-read-count
                               target #'snap-closure-read-multi-gets :metadata)))
              (format *standard-output*
                      "~&; closure walk reads: nodes=~D reference-point-reads=~D ~
level-multi-gets=~D (trie-node ~D, metadata ~D) levels=~D~%"
                      n (+ n n 1) calls node-gets proof-gets levels)
              (is (eq :closed reason))
              (is (= n nodes))
              (is (<= 2 node-gets bound))
              (is (<= proof-gets (+ (ceiling (1+ n) ethereum-lisp.database:+kv-get-many-max-keys+)
                                    levels)))
              (is (= calls (+ node-gets proof-gets)))
              (is (< calls (/ n 100))))
            ;; The same set, and never a node under the proof.
            (is (= n (length visited)))
            (let ((set (make-hash-table :test #'equalp))
                  (position (make-hash-table :test #'equalp)))
              (dolist (hash reference) (setf (gethash hash set) t))
              (is (every (lambda (hash) (gethash hash set)) visited))
              (is (not (nth-value 1 (gethash proved set))))
              ;; The order guaranteed: breadth first from the root, each node
              ;; after a parent that reached it.
              (loop for hash in visited for index from 0
                    do (setf (gethash hash position) index))
              (is (bytes= root-bytes (first visited)))
              (let ((earliest-parent (make-hash-table :test #'equalp)))
                (dolist (hash visited)
                  (dolist (child (snap-marker-node-children
                                  (trie-node-store-get target hash)))
                    (when (gethash child position)
                      (setf (gethash child earliest-parent)
                            (min (gethash hash position)
                                 (gethash child earliest-parent
                                          most-positive-fixnum))))))
                (is (every (lambda (hash)
                             (or (bytes= hash root-bytes)
                                 (< (gethash hash earliest-parent
                                             most-positive-fixnum)
                                    (gethash hash position))))
                           visited))))
            ;; The publisher deletes the markers of exactly that set, keeps
            ;; the ones under the proof, publishes, and reports the attempt.
            (multiple-value-bind (outcome profile)
                (ethereum-lisp.snap-sync::snap-sync-publish-storage-root-closure
                 target state-root account-hash storage-root)
              (is (eq :closed outcome))
              (is (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
                   target root-bytes :storage-root))
              (let ((markers (snap-marker-markers target)))
                (is (= (hash-table-count below-proof)
                       (hash-table-count markers)))
                (is (loop for hash being the hash-keys of below-proof
                          always (nth-value 1 (gethash hash markers)))))
              (is (eq :closed
                      (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-outcome
                       profile)))
              (is (= n (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-nodes-visited
                        profile)))
              (is (= levels (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-levels
                             profile)))
              ;; Cursor set, walk, and the grouped marker lookup.
              (is (= (+ 1 calls
                        (ceiling n ethereum-lisp.database:+kv-get-many-max-keys+))
                     (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-multi-gets
                      profile)))
              (is (integerp
                   (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-elapsed-ms
                    profile))))
            (multiple-value-bind (outcome profile)
                (ethereum-lisp.snap-sync::snap-sync-publish-storage-root-closure
                 target state-root account-hash storage-root)
              (is (eq :already-closed outcome))
              (is (zerop (ethereum-lisp.snap-sync:snap-sync-storage-closure-profile-nodes-visited
                          profile))))))))))

(defun snap-closure-level-widths (database root)
  "Breadth-first node counts per level of the trie under ROOT, first reach wins."
  (let ((seen (make-hash-table :test #'equalp))
        (frontier (list (copy-seq root)))
        (widths '()))
    (setf (gethash (first frontier) seen) t)
    (loop while frontier
          do (push (length frontier) widths)
             (let ((next '()))
               (dolist (hash frontier)
                 (dolist (child (snap-marker-node-children
                                 (trie-node-store-get database hash)))
                   (unless (nth-value 1 (gethash child seen))
                     (setf (gethash child seen) t)
                     (push child next))))
               (setf frontier next)))
    (nreverse widths)))

(deftest snap-storage-root-closure-refuses-too-wide-before-reading-the-level
  (:layer :unit :module :p2p)
  ;; The width bound is judged once a level's proofs are known and before its
  ;; nodes are read, so a trie too wide to close costs the levels that fit plus
  ;; one proof lookup -- never the level that would exceed the bound.  RED (the
  ;; walk at 8933d407): it counted node by node and read all but one of that
  ;; level's nodes, one point read each, before refusing.
  (let ((trie (make-mpt))
        (target (make-instance 'snap-closure-read-counting-database)))
    (loop for slot from 1 to 600
          do (ethereum-lisp.trie::mpt-put
              trie
              (keccak-256 (hash32-bytes (snap-density-slot 1 slot)))
              (rlp-encode (+ 90000 slot))))
    (is (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p target))
    (let* ((storage-root (ethereum-lisp.trie::mpt-persist target trie))
           (widths (snap-closure-level-widths target (hash32-bytes storage-root)))
           (prefix (+ (first widths) (second widths))))
      (is (>= (length widths) 4))
      ;; Every level fits one multi-get, so each costs exactly two.
      (is (every (lambda (width)
                   (<= width ethereum-lisp.database:+kv-get-many-max-keys+))
                 widths))
      ;; A bound one short of the third level's end.
      (let ((ethereum-lisp.snap-sync::*snap-sync-storage-root-closure-max-nodes*
              (+ prefix (third widths) -1)))
        (snap-closure-read-reset target)
        (multiple-value-bind (visited reason calls levels nodes)
            (ethereum-lisp.snap-sync::snap-sync-storage-root-closure-walk
             target storage-root)
          (is (eq :too-wide reason))
          (is (null visited))
          ;; RED at 8933d407: 2 * (bound + 1) point reads here.
          (is (zerop (hash-table-count (snap-closure-read-point-gets target))))
          ;; Exactly the first two levels' nodes were read.
          (is (= prefix (hash-table-count
                         (snap-closure-read-trie-node-keys target))))
          ;; proofs, nodes, proofs, nodes, proofs -- and no fourth read.
          (is (equal '(:metadata :trie-node :metadata :trie-node :metadata)
                     (mapcar #'car (reverse (snap-closure-read-calls target)))))
          (is (= 5 calls))
          (is (= 3 levels))
          (is (= prefix nodes))))
      ;; At exactly the third level's end the third level is read and the
      ;; walk goes on: the bound admits, it does not stop short.
      (let ((ethereum-lisp.snap-sync::*snap-sync-storage-root-closure-max-nodes*
              (+ prefix (third widths))))
        (snap-closure-read-reset target)
        (multiple-value-bind (visited reason calls levels nodes)
            (ethereum-lisp.snap-sync::snap-sync-storage-root-closure-walk
             target storage-root)
          (is (null visited))
          (is (eq :too-wide reason))
          (is (= 7 calls))
          (is (= 4 levels))
          (is (= (+ prefix (third widths)) nodes))))
      ;; Unbounded, the calls alternate proofs and nodes, one pair per level,
      ;; each as wide as the level.
      (snap-closure-read-reset target)
      (multiple-value-bind (visited reason calls levels nodes)
          (ethereum-lisp.snap-sync::snap-sync-storage-root-closure-walk
           target storage-root)
        (is (eq :closed reason))
        (is (= (length widths) levels))
        (is (= (* 2 levels) calls))
        (is (= (reduce #'+ widths) nodes (length visited)))
        (is (equal (loop for width in widths
                         append (list (cons :metadata width)
                                      (cons :trie-node width)))
                   (reverse (snap-closure-read-calls target))))))))
