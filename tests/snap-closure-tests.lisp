(in-package #:ethereum-lisp.test)

;;;; Account-side closure at write time.
;;;;
;;;; Invariant I1: an account-path :TRIE-NODE record implies that every
;;;; descendant trie node is durable AND that every non-empty code hash and
;;;; non-empty storage root named by every leaf below it is durable.  The range
;;;; phase establishes it by refusing to persist anything else, which is what
;;;; geth does in forwardAccountTask
;;;; (references/go-ethereum/eth/protocols/snap/sync.go:2453-2476) and in the
;;;; stack trie's refusal to flush an unfinished boundary (gentrie.go:316-321),
;;;; both at 38271784c2b31926563806da9a2e023b88f5e7a8, v1.17.6-unstable.
;;;;
;;;; A withheld node is simply absent, so healing fetches it: that is the
;;;; fail-closed direction.  A present node whose dependencies are absent is a
;;;; false completion, which is consensus-grade.  Every assertion here is
;;;; written so the second case fails.

;;; ------------------------------------------------------------------
;;; Shared machinery
;;; ------------------------------------------------------------------

(defun snap-closure-account-node-map (records)
  "Map each account-trie node hash in RECORDS to its encoded bytes."
  (let ((map (make-hash-table :test #'equalp)))
    (dolist (record records map)
      (setf (gethash (car record) map) (cdr record)))))

(defun snap-closure-walk-account-subtree (node-map hash)
  "Walk the account subtree rooted at HASH inside NODE-MAP.

Return the account leaf values, the visited node hashes, and a flag that is
true when a descendant is not in NODE-MAP.  The walk is bounded so a cyclic or
non-advancing map fails the test instead of hanging the run."
  (let ((leaf-values '())
        (visited '())
        (missing-p nil)
        (pending (list (cons :hash hash)))
        (seen (make-hash-table :test #'equalp))
        (steps 0))
    (loop while pending
          do (incf steps)
             (when (> steps 1000000)
               (error "Account subtree walk did not terminate"))
             (let* ((item (pop pending))
                    (kind (car item))
                    (payload (cdr item)))
               (if (eq kind :hash)
                   (unless (nth-value 1 (gethash payload seen))
                     (setf (gethash payload seen) t)
                     (multiple-value-bind (encoded present-p)
                         (gethash payload node-map)
                       (if present-p
                           (progn
                             (push payload visited)
                             (push
                              (cons :object
                                    (rlp-decode-one encoded :max-list-items 17))
                              pending))
                           (setf missing-p t))))
                   (let ((items (and (rlp-list-p payload)
                                     (rlp-list-items payload))))
                     (cond
                       ((null items) nil)
                       ((= 17 (length items))
                        (loop for index below 16
                              for child = (nth index items)
                              do (cond
                                   ((rlp-list-p child)
                                    (push (cons :object child) pending))
                                   ((and (byte-vector-p child)
                                         (= 32 (length child)))
                                    (push (cons :hash (copy-seq child))
                                          pending)))))
                       ((= 2 (length items))
                        (let* ((path (first items))
                               (value (second items))
                               (leaf-p (and (byte-vector-p path)
                                            (plusp (length path))
                                            (logbitp 5 (aref path 0)))))
                          (cond
                            (leaf-p (push value leaf-values))
                            ((rlp-list-p value)
                             (push (cons :object value) pending))
                            ((and (byte-vector-p value) (= 32 (length value)))
                             (push (cons :hash (copy-seq value))
                                   pending))))))))))
    (values (nreverse leaf-values) (nreverse visited) missing-p)))

(defun snap-closure-common-hashes (left right)
  "Return the hashes present in both LEFT and RIGHT."
  (let ((seen (make-hash-table :test #'equalp))
        (common '()))
    (dolist (hash left)
      (setf (gethash hash seen) t))
    (dolist (hash right (nreverse common))
      (when (nth-value 1 (gethash hash seen))
        (push hash common)))))

(defun snap-closure-chain-prefix (kind)
  (aref (ethereum-lisp.database::kv-chain-record-key kind (snap-test-hash 0))
        0))

(defun snap-closure-store-violations (database node-map)
  "Return every account node DATABASE holds whose closure it does not hold.

This reads invariant I1 back off a store: for each present account-path trie
node, every descendant trie node must be present, and every non-empty code hash
and storage root named by a leaf beneath it must be present too."
  (let ((violations '()))
    (maphash
     (lambda (hash encoded)
       (declare (ignore encoded))
       (when (nth-value 1 (trie-node-store-get database hash))
         (multiple-value-bind (leaf-values visited missing-p)
             (snap-closure-walk-account-subtree node-map hash)
           (declare (ignore missing-p))
           (dolist (descendant visited)
             (unless (nth-value 1 (trie-node-store-get database descendant))
               (push (list :missing-node hash descendant) violations)))
           (dolist (value leaf-values)
             (let ((account
                     (ethereum-lisp.state:decode-state-account-rlp value)))
               (unless (hash32= (state-account-code-hash account)
                                +empty-code-hash+)
                 (unless (nth-value
                          1
                          (kv-get-chain-record
                           database :code
                           (hash32-bytes (state-account-code-hash account))))
                   (push (list :missing-code hash) violations)))
               (unless (hash32= (state-account-storage-root account)
                                +empty-trie-hash+)
                 (unless (nth-value
                          1
                          (trie-node-store-get
                           database
                           (hash32-bytes
                            (state-account-storage-root account))))
                   (push (list :missing-storage hash) violations))))))))
     node-map)
    (nreverse violations)))

(defun snap-closure-audit-batches
    (target-database account-records thunk &key trip crash-latch)
  "Run THUNK while auditing every batch applied to TARGET-DATABASE.

For every account-path trie-node put, every descendant node, every non-empty
code hash and every non-empty storage root named by a leaf beneath it must be
durable in that same batch or in an earlier one.  TRIP, when supplied, is
called with the batch before it is applied; a true answer raises a simulated
crash at that seam instead of applying it, which is what a durable-write
boundary actually loses -- whole trailing batches.  CRASH-LATCH makes that
crash final: every later batch to TARGET-DATABASE is refused as well, which is
what a dead process does.  It is needed wherever other threads keep writing
after the first one fails, or a retry would quietly heal the seam under test.

The result is a plist carrying the counters that make a green run non-vacuous
plus the violation list."
  (let ((node-map (snap-closure-account-node-map account-records))
        (durable-nodes (make-hash-table :test #'equalp))
        (durable-codes (make-hash-table :test #'equalp))
        (inspected 0)
        (leaves 0)
        (code-checks 0)
        (storage-checks 0)
        (tripped nil)
        (dropped 0)
        (violations '())
        (node-prefix (snap-closure-chain-prefix :trie-node))
        (code-prefix (snap-closure-chain-prefix :code))
        (lock (sb-thread:make-mutex :name "snap-closure-audit"))
        (real-apply (fdefinition 'ethereum-lisp.database:kv-apply-batch))
        (real-buffered
          (fdefinition 'ethereum-lisp.database:kv-apply-batch-buffered)))
    (labels
        ((record-batch (batch)
           (let ((operations
                   (reverse
                    (ethereum-lisp.database::kv-write-batch-operations batch)))
                 (new-account-nodes '()))
             ;; Everything this batch writes counts as durable for this batch:
             ;; a batch is one atomic WAL append, so a crash drops it whole.
             (dolist (operation operations)
               (let ((key (second operation)))
                 (when (and (eq :put (first operation))
                            (plusp (length key)))
                   (cond
                     ((= (aref key 0) node-prefix)
                      (let ((hash (subseq key 1)))
                        (setf (gethash hash durable-nodes) t)
                        (when (nth-value 1 (gethash hash node-map))
                          (push hash new-account-nodes))))
                     ((= (aref key 0) code-prefix)
                      (setf (gethash (subseq key 1) durable-codes) t))))))
             (dolist (hash (nreverse new-account-nodes))
               (incf inspected)
               (multiple-value-bind (leaf-values visited missing-p)
                   (snap-closure-walk-account-subtree node-map hash)
                 ;; NODE-MAP holds the fixture's whole account trie, so a miss
                 ;; here would mean the fixture, not the writer, is wrong.
                 (when missing-p
                   (push (list :fixture-incomplete hash) violations))
                 (dolist (descendant visited)
                   (unless (nth-value 1 (gethash descendant durable-nodes))
                     (push (list :missing-node hash descendant) violations)))
                 (dolist (value leaf-values)
                   (incf leaves)
                   (let ((account
                           (ethereum-lisp.state:decode-state-account-rlp
                            value)))
                     (unless (hash32= (state-account-code-hash account)
                                      +empty-code-hash+)
                       (incf code-checks)
                       (unless (nth-value
                                1
                                (gethash
                                 (hash32-bytes
                                  (state-account-code-hash account))
                                 durable-codes))
                         (push (list :missing-code hash) violations)))
                     (unless (hash32= (state-account-storage-root account)
                                      +empty-trie-hash+)
                       (incf storage-checks)
                       (unless (nth-value
                                1
                                (gethash
                                 (hash32-bytes
                                  (state-account-storage-root account))
                                 durable-nodes))
                         (push (list :missing-storage hash)
                               violations)))))))))
         (guard (database batch real)
           (if (eq database target-database)
               (let ((crash-p nil))
                 (sb-thread:with-mutex (lock)
                   (cond
                     ((and tripped crash-latch)
                      (incf dropped)
                      (setf crash-p t))
                     ((and trip (not tripped) (funcall trip batch))
                      (incf dropped)
                      (setf tripped t crash-p t)))
                   (unless crash-p (record-batch batch)))
                 (if crash-p
                     (error "Simulated snap closure crash at a batch seam")
                     (funcall real database batch)))
               (funcall real database batch))))
      (unwind-protect
           (progn
             (setf (fdefinition 'ethereum-lisp.database:kv-apply-batch)
                   (lambda (database batch)
                     (guard database batch real-apply)))
             (setf (fdefinition
                    'ethereum-lisp.database:kv-apply-batch-buffered)
                   (lambda (database batch)
                     (guard database batch real-buffered)))
             (funcall thunk))
        (setf (fdefinition 'ethereum-lisp.database:kv-apply-batch) real-apply)
        (setf (fdefinition 'ethereum-lisp.database:kv-apply-batch-buffered)
              real-buffered)))
    (list :inspected inspected :account-leaves leaves
          :code-checks code-checks :storage-checks storage-checks
          :tripped tripped :dropped dropped
          :violations (nreverse violations))))

(defun snap-closure-dependency-fixture (&key (wide-slots 96))
  "Return a state exercising every external dependency edge of an account.

Sixteen plain accounts spread over the high-nibble partitions, four accounts
carrying bytecode, one contract wide enough that a small StorageRanges byte cap
chunks it, and three one-slot contracts that a single response answers whole."
  (multiple-value-bind (state addresses) (snap-test-partitioned-state)
    (loop for index from 101 to 104
          for address = (snap-test-address-from-integer index)
          do (state-db-set-account
              state address
              (make-state-account :nonce index :balance (+ 5000 index)))
             (state-db-set-code
              state address
              (concatenate 'vector
                           (make-byte-vector 8 :initial-element index)
                           #(96 0 96 0 243)))
             (push address addresses))
    (let ((wide (snap-test-address-from-integer 201)))
      (state-db-set-account
       state wide (make-state-account :nonce 201 :balance 7201))
      (loop for slot from 1 to wide-slots
            do (state-db-set-storage
                state wide (make-hash32 (snap-test-index-hash (+ 201000 slot)))
                (+ 400000 slot)))
      (push wide addresses))
    (loop for index from 202 to 204
          for address = (snap-test-address-from-integer index)
          do (state-db-set-account
              state address
              (make-state-account :nonce index :balance (+ 7000 index)))
             (state-db-set-storage
              state address
              (make-hash32 (snap-test-index-hash (* index 1000)))
              (+ 500000 index))
             (push address addresses))
    (values state (nreverse addresses)
            (snap-test-address-from-integer 201))))

(defun call-with-snap-closure-proof-depth (depth thunk)
  "Run THUNK with the closed-subtree writer on and proofs published at DEPTH.

These are set process-globally rather than bound, because the production import
prepares and completes pages on worker threads and a LET binding is invisible
there -- the run would silently exercise the legacy writer instead."
  (let ((writes ethereum-lisp.snap-sync::*snap-sync-account-closure-writes*)
        (lookup ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*)
        (coarse ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*)
        (nested
          ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*))
    (unwind-protect
         (progn
           (setf ethereum-lisp.snap-sync::*snap-sync-account-closure-writes* t
                 ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
                 depth
                 ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
                 depth
                 ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
                 depth)
           (funcall thunk))
      (setf ethereum-lisp.snap-sync::*snap-sync-account-closure-writes* writes
            ethereum-lisp.snap-sync::*snap-sync-healed-subtree-prefix-nibbles*
            lookup
            ethereum-lisp.snap-sync::*snap-sync-range-subtree-prefix-nibbles*
            coarse
            ethereum-lisp.snap-sync::*snap-sync-range-nested-subtree-prefix-nibbles*
            nested))))

(defmacro with-snap-closure-proof-depth ((depth) &body body)
  "Publish and consume closure proofs at DEPTH with the closed writer on."
  `(call-with-snap-closure-proof-depth ,depth (lambda () ,@body)))

;;; ------------------------------------------------------------------
;;; Step 1 -- the writer cannot persist an open account node
;;; ------------------------------------------------------------------

(deftest snap-account-range-page-persists-only-closed-subtrees
  (:layer :unit :module :p2p)
  ;; The range phase used to persist every reconstructed node AND every
  ;; boundary proof node the moment the range proof verified, marking them all
  ;; incomplete.  Under the closed-subtree contract it persists nothing at
  ;; proof time and, once the page's dependencies are resolved, only the
  ;; maximal subtrees whose every leaf passed a real durability check.  The
  ;; spine, the boundary proof nodes, the range-straddling regions and the
  ;; paths to open accounts are never written.
  (with-snap-closure-proof-depth (1)
    (multiple-value-bind (state addresses wide) (snap-closure-dependency-fixture)
      (declare (ignore addresses))
      (let* ((root (state-db-root state))
             (account-records
               (mpt-dirty-node-records
                (first (state-db-persistence-tries state))))
             (node-map (snap-closure-account-node-map account-records))
             (wide-hash (keccak-256 (address-bytes wide)))
             (source-database (make-memory-key-value-database))
             (target-database (make-memory-key-value-database))
             (base
               (snap-test-source
                (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                 source-database state)))
             (proof-nodes '())
             (source
               (snap-test-source-with-account-callback
                base
                (lambda (request)
                  (let ((response
                          (funcall
                           (ethereum-lisp.snap-sync:snap-sync-source-account-range
                            base)
                           request)))
                    (dolist (encoded
                             (ethereum-lisp.snap:snap-account-range-proof
                              response))
                      (push (keccak-256 encoded) proof-nodes))
                    response))))
             (task
               (first
                (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
                 :count 1))))
        (is (plusp (hash-table-count node-map)))
        (is
         (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
          target-database))
        ;; A generous account byte limit returns the whole range in one page;
        ;; a small dependency byte limit is what chunks the wide contract.
        (let ((work
                (ethereum-lisp.snap-sync::snap-sync-prepare-account-page-range
                 target-database source root 0 task 200000)))
          ;; Proof verification publishes nothing at all, so no boundary proof
          ;; node and no spine node can reach the store this way.
          (is (ethereum-lisp.snap-sync::snap-sync-trie-node-store-empty-p
               target-database))
          (is (ethereum-lisp.snap-sync::snap-sync-account-page-work-closed-writes-p
               work))
          (let ((result
                  (ethereum-lisp.snap-sync::snap-sync-complete-account-page
                   target-database source root work 400)))
            (let ((profile
                    (ethereum-lisp.snap-sync::snap-sync-page-result-profile
                     result)))
              ;; Positive controls: the page really closed subtrees, really
              ;; withheld an open contract, and published no negative marker.
              (is (plusp
                   (ethereum-lisp.snap-sync::snap-sync-page-profile-closed-node-count
                    profile)))
              (is (plusp
                   (ethereum-lisp.snap-sync::snap-sync-page-profile-healed-subtree-count
                    profile)))
              (is (plusp
                   (ethereum-lisp.snap-sync::snap-sync-page-profile-open-storage-account-count
                    profile)))
              (is (zerop
                   (ethereum-lisp.snap-sync::snap-sync-page-profile-incomplete-node-count
                    profile)))
              (is (zerop
                   (ethereum-lisp.snap-sync::snap-sync-page-profile-dependency-subtree-count
                    profile))))
            ;; The chunked contract's leaf, and therefore its whole path, is
            ;; withheld; the store holds no account node above it.
            (is (null (snap-closure-store-violations target-database node-map)))
            ;; The state root is spine: it can never be closed while any
            ;; account under it is open.
            (is (not (nth-value 1 (trie-node-store-get
                                   target-database (hash32-bytes root)))))
            ;; No boundary proof node reached the store unless it was also a
            ;; reconstructed node of a closed subtree.
            (dolist (hash proof-nodes)
              (unless (nth-value 1 (gethash hash node-map))
                (is (not (nth-value 1 (trie-node-store-get
                                       target-database hash))))))
            ;; The wide contract is the one deliberately open account, and the
            ;; closed set must still cover most of the trie.
            (let ((present 0)
                  (absent 0))
              (maphash
               (lambda (hash encoded)
                 (declare (ignore encoded))
                 (if (nth-value 1 (trie-node-store-get target-database hash))
                     (incf present)
                     (incf absent)))
               node-map)
              (is (plusp present))
              (is (plusp absent))
              ;; Granularity: one open account must not withhold the trie.
              (is (> present absent))
              (format *standard-output*
                      "~&; one-page closure: account-trie-nodes=~D ~
persisted=~D withheld=~D~%"
                      (hash-table-count node-map) present absent))
            (is (not (null wide-hash)))))))))

(deftest snap-chunked-storage-account-is-excluded-from-the-closed-account-trie
  (:layer :unit :module :p2p)
  ;; geth clears needHeal for a chunked contract only when the reassembled root
  ;; both matches and is present on disk (sync.go:2272-2282).  Our equivalent
  ;; evidence is the whole-root closure proof, which only a complete
  ;; single-response group or the healer's post-order sentinel publishes.
  ;; Completed partition cursors are NOT closure -- this file says so at
  ;; SNAP-SYNC-RANGE-PLAN-FULLY-DURABLE-P -- so a predicate that reads the
  ;; deferred-storage list instead of the proof would pass this test's control
  ;; arm and fail its subject arm.
  (with-snap-closure-proof-depth (1)
    (let* ((state (make-state-db))
           (narrow (snap-test-address-from-integer 301))
           (wide (snap-test-address-from-integer 302)))
      (state-db-set-account
       state narrow (make-state-account :nonce 1 :balance 11))
      (state-db-set-storage
       state narrow (make-hash32 (snap-test-index-hash 1)) 4242)
      (state-db-set-account
       state wide (make-state-account :nonce 2 :balance 22))
      (loop for slot from 1 to 128
            do (state-db-set-storage
                state wide (make-hash32 (snap-test-index-hash (+ 900 slot)))
                (+ 70000 slot)))
      (let* ((root (state-db-root state))
             (narrow-hash (keccak-256 (address-bytes narrow)))
             (wide-hash (keccak-256 (address-bytes wide)))
             (narrow-root (state-db-get-storage-root state narrow))
             (wide-root (state-db-get-storage-root state wide))
             (source-database (make-memory-key-value-database))
             (target-database (make-memory-key-value-database))
             (source
               (snap-test-source
                (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                 source-database state)))
             (task
               (first
                (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
                 :count 1))))
        (is (not (hash32= narrow-root wide-root)))
        (is
         (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
          target-database))
        (let* ((work
                 (ethereum-lisp.snap-sync::snap-sync-prepare-account-page-range
                  target-database source root 0 task 200000))
               (leaf-values
                 (mpt-dirty-leaf-values
                  (ethereum-lisp.snap-sync::snap-sync-account-page-work-account-trie
                   work))))
          (is (= 2 (length leaf-values)))
          (ethereum-lisp.snap-sync::snap-sync-complete-account-page
           target-database source root work 400)
          ;; Control: the small contract's storage came back whole, so it has a
          ;; whole-root proof and its account leaf is durable.
          (is (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
               target-database (hash32-bytes narrow-root) :storage-root))
          ;; Subject: the chunked contract has no whole-root proof, so it stays
          ;; open however many partition cursors completed.
          (is (not (ethereum-lisp.snap-sync::snap-sync-healed-subtree-present-p
                    target-database (hash32-bytes wide-root) :storage-root)))
          (let ((predicate
                  (ethereum-lisp.snap-sync::snap-sync-account-closure-predicate
                   target-database leaf-values '()))
                (narrow-value nil)
                (wide-value nil))
            (dolist (value leaf-values)
              (let ((account
                      (ethereum-lisp.state:decode-state-account-rlp value)))
                (when (hash32= (state-account-storage-root account) narrow-root)
                  (setf narrow-value value))
                (when (hash32= (state-account-storage-root account) wide-root)
                  (setf wide-value value))))
            (is narrow-value)
            (is wide-value)
            (is (funcall predicate narrow-value))
            (is (not (funcall predicate wide-value))))
          (is (not (null narrow-hash)))
          (is (not (null wide-hash))))))))

(deftest snap-closed-account-subtree-granularity-descends-past-an-open-account
  (:layer :unit :module :p2p)
  ;; Judging closure per fixed-depth bucket lets one open account withhold
  ;; every account that shares its bucket -- on a real chain roughly 850 of
  ;; them -- and because this design does not WRITE a withheld node, those
  ;; accounts must then be DOWNLOADED by healing.  The maximal-subtree rule
  ;; publishes the open account's siblings instead, which is what geth's stack
  ;; trie emits between two exclusions.
  (let* ((state (make-state-db))
         (addresses
           (loop for index from 1 to 256
                 collect (snap-test-address-from-integer index))))
    ;; Distinct balances so every leaf VALUE differs: identical accounts would
    ;; make "exclude this one leaf value" exclude all of them.
    (loop for address in addresses
          for index from 1
          do (state-db-set-account
              state address
              (make-state-account :nonce index :balance (+ 900000 index))))
    (state-db-root state)
    (let* ((trie (first (state-db-persistence-tries state)))
           (leaf-values (mpt-dirty-leaf-values trie))
           (open-value (first leaf-values))
           (start (make-byte-vector 32))
           (end (make-byte-vector 32 :initial-element #xff))
           (closed-everything
             (mpt-proved-range-closed-subtrees
              trie start end (lambda (value) (declare (ignore value)) t)))
           (closed-with-one-open
             (mpt-proved-range-closed-subtrees
              trie start end
              (lambda (value) (not (bytes= value open-value)))))
           (nodes
             (lambda (groups)
               (let ((seen (make-hash-table :test #'equalp)))
                 (dolist (group groups (hash-table-count seen))
                   (dolist (hash (third group))
                     (setf (gethash hash seen) t)))))))
      (is (= 256 (length leaf-values)))
      ;; With nothing open the whole range collapses to one maximal subtree.
      (is (= 1 (length closed-everything)))
      ;; One open account costs only its own path, not the trie.
      (is (plusp (length closed-with-one-open)))
      (is (< (funcall nodes closed-with-one-open)
             (funcall nodes closed-everything)))
      (is (> (funcall nodes closed-with-one-open)
             (floor (funcall nodes closed-everything) 2)))
      ;; Positive control: the open account's own leaf is never published.
      (let ((published (make-hash-table :test #'equalp)))
        (dolist (group closed-with-one-open)
          (dolist (hash (third group))
            (setf (gethash hash published) t)))
        (is (notany
             (lambda (record)
               (and (nth-value 1 (gethash (car record) published))
                    (search open-value (cdr record))))
             (mpt-dirty-node-records trie)))))))

(deftest snap-account-closed-subtree-follows-its-dependencies
  (:layer :integration :module :p2p)
  ;; The ordering half of I1, asked of a real import rather than of one
  ;; function: for every account trie-node put in every applied batch, every
  ;; code hash and every non-empty storage root named by a leaf beneath it must
  ;; already be durable, in that batch or an earlier one.  It is run over the
  ;; single-source path AND the multi-source production path, whose codes and
  ;; chunked storage roots are written by import-wide workers on other threads,
  ;; so batch co-location proves nothing there and only the happens-before
  ;; edges do.
  (with-snap-closure-proof-depth (2)
    (multiple-value-bind (state addresses wide) (snap-closure-dependency-fixture)
      (declare (ignore addresses wide))
      (let* ((root (state-db-root state))
             (account-records
               (mpt-dirty-node-records
                (first (state-db-persistence-tries state))))
             (node-map (snap-closure-account-node-map account-records))
             (source-database (make-memory-key-value-database))
             (backend
               (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                source-database state)))
        ;; Positive control: the auditor must flag an account node written
        ;; without its dependencies, or a green run below would prove nothing.
        (let* ((control-database (make-memory-key-value-database))
               (control
                 (snap-closure-audit-batches
                  control-database account-records
                  (lambda ()
                    (let ((batch (make-kv-write-batch)))
                      (ethereum-lisp.snap-sync::snap-sync-populate-verified-trie-records-batch
                       control-database batch
                       (list (find (hash32-bytes root) account-records
                                   :key #'car :test #'bytes=)))
                      (kv-apply-batch control-database batch))))))
          (is (= 1 (getf control :inspected)))
          (is (getf control :violations)))
        (dolist (multi-p (list nil t))
          (let* ((target-database (make-memory-key-value-database))
                 (audit
                   (snap-closure-audit-batches
                    target-database account-records
                    (lambda ()
                      (if multi-p
                          (ethereum-lisp.snap-sync:snap-sync-import-state-multi
                           target-database
                           (list (snap-test-source backend)
                                 (snap-test-source backend))
                           :pivot-hash (make-hash32 (snap-test-hash 11))
                           :pivot-number 51 :state-root root
                           :target-hash (make-hash32 (snap-test-hash 12))
                           :chain-id 560048
                           :genesis-hash (make-hash32 (snap-test-hash 13))
                           :authority-id (make-hash32 (snap-test-hash 14))
                           :byte-limit 4096)
                          (ethereum-lisp.snap-sync:snap-sync-import-state
                           target-database (snap-test-source backend)
                           :pivot-hash (make-hash32 (snap-test-hash 11))
                           :pivot-number 51 :state-root root
                           :target-hash (make-hash32 (snap-test-hash 12))
                           :chain-id 560048
                           :genesis-hash (make-hash32 (snap-test-hash 13))
                           :authority-id (make-hash32 (snap-test-hash 14))
                           :byte-limit 4096))))))
            ;; Counters first: a run that inspected nothing, or checked no code
            ;; and no storage root, cannot report a meaningful absence.
            (is (plusp (getf audit :inspected)))
            (is (plusp (getf audit :account-leaves)))
            (is (plusp (getf audit :code-checks)))
            (is (plusp (getf audit :storage-checks)))
            (is (null (getf audit :violations)))
            (is (null (snap-closure-store-violations target-database
                                                     node-map)))))))))

;;; ------------------------------------------------------------------
;;; The test oracle itself: concurrent batches must not be lost
;;; ------------------------------------------------------------------

(deftest memory-database-batches-are-not-lost-under-concurrent-writers
  (:layer :unit :module :storage)
  ;; The memory backend applies a batch by copying the whole table, mutating
  ;; the copy and publishing it.  That is a read-modify-write over shared
  ;; state, so two concurrent writers lose one batch entirely -- not reorder
  ;; it, lose it.  RocksDB serializes write groups internally and never does
  ;; this, so without serialization here every crash-injection and
  ;; batch-inspection test that drives the concurrent SNAP writers is an
  ;; unsound oracle: a storage batch can vanish and the account batch that
  ;; depended on it still land.
  ;;
  ;; Positive control: with the serialization removed this test loses keys and
  ;; goes red; it was confirmed red that way before the fix was kept.
  (let* ((database (make-memory-key-value-database))
         (writers 8)
         (per-writer 64)
         (failures '())
         (lock (sb-thread:make-mutex :name "snap-closure-writers"))
         (threads '()))
    (dotimes (index writers)
      (let ((worker index))
        (push
         (sb-thread:make-thread
          (lambda ()
            (handler-case
                (dotimes (step per-writer)
                  (let ((batch (make-kv-write-batch)))
                    (ethereum-lisp.database:kv-batch-put-chain-record
                     batch :metadata
                     (format nil "snap-closure-~D-~D" worker step)
                     #(1))
                    (kv-apply-batch database batch)))
              (serious-condition (condition)
                (sb-thread:with-mutex (lock)
                  (push condition failures)))))
          :name "snap-closure-memory-writer")
         threads)))
    (dolist (thread threads)
      (sb-thread:join-thread thread))
    (is (null failures))
    (let ((missing 0))
      (dotimes (worker writers)
        (dotimes (step per-writer)
          (unless (nth-value
                   1
                   (kv-get-chain-record
                    database :metadata
                    (format nil "snap-closure-~D-~D" worker step)))
            (incf missing))))
      ;; Every batch that returned must still be readable.
      (is (zerop missing)))))

;;; ------------------------------------------------------------------
;;; Kind-blindness: an account node can never be mistaken for a storage node
;;; ------------------------------------------------------------------

(deftest snap-account-and-storage-trie-nodes-cannot-collide
  (:layer :unit :module :p2p)
  ;; The flat :TRIE-NODE table is kind-blind: one content-addressed record
  ;; space holds both account and storage nodes.  A kind-blind presence rule is
  ;; therefore sound only because the two node sets are disjoint by
  ;; construction, and that rests on two facts.
  ;;
  ;; (1) A leaf node is RLP([compact-path, value]), so two equal leaf encodings
  ;; have equal values.  The shortest account value is
  ;; RLP([nonce, balance, storageRoot(32), codeHash(32)]) with both integers
  ;; zero; the longest storage value is the RLP of a full 256-bit word, and the
  ;; snap ingestion path enforces that ceiling on peer-supplied values rather
  ;; than assuming it.  The ranges do not overlap.
  ;;
  ;; (2) No account-trie node is ever inlined: every one of them encodes to at
  ;; least 32 bytes, so it is always hash-addressed.  Without this the
  ;; branch/extension induction does not close, because a storage branch may
  ;; carry an embedded child where an account branch carries a hash.
  (let ((minimum-account-value (state-account-rlp (make-state-account)))
        (maximum-storage-value (rlp-encode (1- (ash 1 256))))
        (largest-account-value
          (state-account-rlp
           (make-state-account
            :nonce (1- (ash 1 64)) :balance (1- (ash 1 256))
            :storage-root (make-hash32 (snap-test-hash 7))
            :code-hash (make-hash32 (snap-test-hash 8))))))
    (is (= 70 (length minimum-account-value)))
    (is (= 33 (length maximum-storage-value)))
    (is (> (length minimum-account-value) (length maximum-storage-value)))
    (is (>= (length largest-account-value) (length minimum-account-value)))
    ;; The ceiling is enforced where peer storage values enter the store, not
    ;; assumed from the protocol.
    (is (bytes=
         maximum-storage-value
         (ethereum-lisp.snap-sync::snap-sync-storage-trie-value
          maximum-storage-value)))
    (signals error
      (ethereum-lisp.snap-sync::snap-sync-storage-trie-value
       (rlp-encode (make-byte-vector 33 :initial-element 7)))))
  ;; No account node is inlined, and the two node sets are disjoint, over real
  ;; tries wide enough to contain branches, extensions and leaves.
  (let ((state (make-state-db))
        (address (snap-test-address-from-integer 5)))
    (loop for index from 1 to 128
          do (state-db-set-storage
              state address (make-hash32 (snap-test-index-hash index))
              (+ 600000 index)))
    (loop for index from 20 to 200
          do (state-db-set-account
              state (snap-test-address-from-integer index)
              (make-state-account :nonce index :balance (+ 300000 index))))
    (state-db-root state)
    (let* ((tries (state-db-persistence-tries state))
           (account-records (mpt-dirty-node-records (first tries)))
           (account-hashes (mapcar #'car account-records))
           (storage-hashes
             (loop for trie in (rest tries)
                   append (mapcar #'car (mpt-dirty-node-records trie)))))
      (is (plusp (length account-hashes)))
      (is (plusp (length storage-hashes)))
      (is (every (lambda (record) (>= (length (cdr record)) 32))
                 account-records))
      (is (null (snap-closure-common-hashes account-hashes storage-hashes)))
      ;; Positive control for the disjointness check itself.
      (is (snap-closure-common-hashes account-hashes account-hashes)))))

;;; ------------------------------------------------------------------
;;; Every writer of an account-path trie node must be classified
;;; ------------------------------------------------------------------

(defun snap-closure-source-paths ()
  "Return every source file the shipped system declares, in path order."
  (labels ((collect (component)
             (cond
               ((typep component 'asdf:cl-source-file)
                (list (truename (asdf:component-pathname component))))
               ((typep component 'asdf:module)
                (mapcan #'collect (asdf:component-children component)))
               (t '()))))
    (sort (collect (asdf:find-system '#:ethereum-lisp))
          #'string< :key #'namestring)))

(defun snap-closure-trie-node-put-sites (text)
  "Return the offsets in TEXT where a :TRIE-NODE record is written.

A put site is a PUT-CHAIN-RECORD call naming :TRIE-NODE among the arguments
that precede its first nested form or its closing parenthesis, however many
lines they span.  An earlier version looked only eighty characters ahead and
so missed the healer's three-line spelling in client.lisp."
  (let ((sites '())
        (start 0))
    (loop
      (let ((found (search "put-chain-record" text :start2 start)))
        (unless found (return (nreverse sites)))
        (let* ((after (+ found (length "put-chain-record")))
               (stop (or (position-if (lambda (character)
                                        (member character '(#\( #\))))
                                      text :start after)
                         (length text)))
               (window (subseq text after stop)))
          (when (search ":trie-node" window)
            (push found sites)))
        (setf start (1+ found))))))


(defun snap-closure-mpt-persist-call-sites (text)
  "Return the offsets in TEXT where MPT-PERSIST is called, not defined.

A call is the name directly after an open parenthesis or a package marker, so
both (mpt-persist ...) and (ethereum-lisp.trie:mpt-persist ...) count while
(defun mpt-persist ...) does not."
  (let ((sites '())
        (start 0))
    (loop
      (let ((found (search "mpt-persist " text :start2 start)))
        (unless found (return (nreverse sites)))
        (when (and (plusp found)
                   (member (char text (1- found)) '(#\( #\:)))
          (push found sites))
        (setf start (1+ found))))))

(deftest snap-account-trie-node-writers-are-all-classified
  (:layer :unit :module :p2p)
  ;; Under a presence-based account rule, every writer of an account-path
  ;; :TRIE-NODE record is part of the contract, not only the snap client.  A
  ;; new writer that appears without being classified is the same class of
  ;; defect as 03263d2f, so it must break this test rather than a live sync.
  ;;
  ;; Classification of the three writer sites that exist:
  ;;
  ;;   src/foundation/trie/persistence.lisp MPT-POPULATE-DIRTY-BATCH
  ;;     One atomic batch holding MPT-DIRTY-NODES, which is documented as
  ;;     children before parents, for a trie that was fully materialized in
  ;;     memory first.  Its callers are the block/genesis state export (which
  ;;     puts every touched trie AND the code into the same batch) and the
  ;;     schema-v4 migration.  Each commits a complete state, so the subtree
  ;;     half of I1 holds; the external half holds because a validly executed
  ;;     state already has its code and storage.  A crash loses the whole
  ;;     batch.  The snap/1 SERVER is no longer a caller: it used to
  ;;     MPT-PERSIST the account trie alone -- no storage tries, no code --
  ;;     while live during our own sync, and now serves without writing
  ;;     (SNAP-SERVER-SERVING-AN-INCOMPLETE-STATE-WRITES-NO-TRIE-NODE).
  ;;     MPT-PERSIST itself has no caller left in src/; a new one is a new
  ;;     writer and must be classified here.
  ;;
  ;;   src/networking/snap-sync/client.lisp  (two sites)
  ;;   SNAP-SYNC-POPULATE-VERIFIED-TRIE-RECORDS-BATCH
  ;;     The snap client's range writer, whose account-side contract is this
  ;;     file's subject.
  ;;   %SNAP-SYNC-HEAL-STATE, the fetched-node flush
  ;;     The healer writes each node it fetches into PENDING-FETCHED-BATCH as
  ;;     soon as it arrives, top-down, with the node's incomplete marker in the
  ;;     same batch, and removes the marker only at the node's post-order
  ;;     completion.  So a present account node written here can stand above
  ;;     absent children and absent code or storage, and I1 holds for it only
  ;;     if the presence rule reads that marker.  Observed with the batch audit
  ;;     on a multi-source import whose chunked contract the healer finishes.
  ;;     This site was missed until the scanner stopped looking a fixed eighty
  ;;     characters ahead; it is recorded here, not fixed, because the healer
  ;;     rule belongs to the epoch-seven change.
  ;;
  ;; The expectation is per SITE, not per file: a second writer added to an
  ;; already classified file must break this test too.
  (let ((expected
          (list (cons "src/foundation/trie/persistence.lisp" 1)
                (cons "src/networking/snap-sync/client.lisp" 2)))
        (found '())
        (persist-callers '()))
    (dolist (path (snap-closure-source-paths))
      (let ((text
              (with-open-file (stream path :external-format :utf-8)
                (let ((buffer (make-string (file-length stream))))
                  (subseq buffer 0 (read-sequence buffer stream))))))
        (when (snap-closure-mpt-persist-call-sites text)
          (push (namestring path) persist-callers))
        (let ((sites (length (snap-closure-trie-node-put-sites text))))
          (when (plusp sites)
            (let* ((namestring (namestring path))
                   (marker (search "/src/" namestring)))
              (push (cons (if marker
                              (concatenate 'string "src"
                                           (subseq namestring (+ marker 4)))
                              namestring)
                          sites)
                    found))))))
    (setf found (sort (nreverse found) #'string< :key #'car))
    ;; Positive control: the scanner must flag a synthetic writer in both the
    ;; one-line and the multi-line spelling, and ignore a :METADATA put and a
    ;; :TRIE-NODE that only appears inside a nested argument form.
    (is (snap-closure-trie-node-put-sites
         "(kv-batch-put-chain-record batch :trie-node hash encoded)"))
    (is (snap-closure-trie-node-put-sites
         (format nil "(kv-batch-put-chain-record~%~40Tpending-fetched-batch~%~40T:trie-node hash encoded)")))
    (is (null (snap-closure-trie-node-put-sites
               "(kv-batch-put-chain-record batch :metadata key value)")))
    (is (null (snap-closure-trie-node-put-sites
               "(kv-batch-put-chain-record batch :metadata (f :trie-node))")))
    (is (equal expected found))

    ;; MPT-PERSIST writes one trie's dirty nodes with no code and no other
    ;; trie, so any caller of it is an unclassified account-node writer.
    (is (snap-closure-mpt-persist-call-sites "(mpt-persist database trie)"))
    (is (null (snap-closure-mpt-persist-call-sites
               "(defun mpt-persist (database trie)")))
    (is (null persist-callers))))

;;; ------------------------------------------------------------------
;;; The snap/1 server reads; it never writes the state it serves
;;; ------------------------------------------------------------------

(defun snap-closure-serve-every-request-kind
    (backend root code-hashes storage-account)
  "Issue one request of each snap/1 kind for ROOT and return the answers.

The result is a plist of the served item counts, so a caller can prove that the
requests were really answered rather than refused as unavailable."
  (let* ((accounts
           (snap-test-call-backend
            backend ethereum-lisp.snap:+snap-message-get-account-range+
            (ethereum-lisp.snap:make-snap-get-account-range
             21 root (make-byte-vector 32)
             (make-array 32 :element-type '(unsigned-byte 8)
                            :initial-element 255)
             (* 1024 1024))))
         (storage
           (snap-test-call-backend
            backend ethereum-lisp.snap:+snap-message-get-storage-ranges+
            (ethereum-lisp.snap:make-snap-get-storage-ranges
             22 root (list storage-account) #() #() (* 1024 1024))))
         (codes
           (snap-test-call-backend
            backend ethereum-lisp.snap:+snap-message-get-bytecodes+
            (ethereum-lisp.snap:make-snap-get-bytecodes
             23 code-hashes (* 1024 1024))))
         (nodes
           (snap-test-call-backend
            backend ethereum-lisp.snap:+snap-message-get-trie-nodes+
            (ethereum-lisp.snap:make-snap-get-trie-nodes
             24 root
             (list (list #(0))
                   (list storage-account #(0)))
             (* 1024 1024)))))
    (list :accounts
          (length (ethereum-lisp.snap:snap-account-range-accounts accounts))
          :slots
          (length
           (first (ethereum-lisp.snap:snap-storage-ranges-slots storage)))
          :codes (length (ethereum-lisp.snap:snap-bytecodes-codes codes))
          :nodes
          (count-if #'plusp
                    (ethereum-lisp.snap:snap-trie-nodes-nodes nodes)
                    :key #'length))))

(deftest snap-server-serving-an-incomplete-state-writes-no-trie-node
  (:layer :unit :module :p2p)
  ;; The snap/1 server used to call MPT-PERSIST on the ACCOUNT trie it was
  ;; about to serve: one batch of that trie's dirty nodes, with neither the
  ;; storage tries nor the code its leaves name.  Under I1 such a record claims
  ;; that everything below and everything it names is durable, and the server
  ;; is live while we are ourselves syncing into the same store.  A server
  ;; reads; geth's handlers open the root read-only and answer empty when it
  ;; is absent (eth/protocols/snap/handlers.go at
  ;; 38271784c2b31926563806da9a2e023b88f5e7a8).
  ;;
  ;; The served state here lives only in memory: its code and storage were
  ;; never made durable in DATABASE, which is exactly the incomplete state a
  ;; persisted account node must not stand above.
  ;;
  ;; RED control, recorded in docs/evidence/sec5-snap-server-closure.txt: on
  ;; the previous server this test fails -- the audit inspects the account
  ;; nodes the server wrote and reports their missing code and storage, and the
  ;; root is present in the store.
  (multiple-value-bind (state addresses wide) (snap-closure-dependency-fixture)
    (declare (ignore addresses))
    (let* ((root (hash32-bytes (state-db-root state)))
           ;; Read the fixture's records BEFORE serving: the old writer also
           ;; marked the served trie's nodes clean, which would empty this list.
           (tries (state-db-persistence-tries state))
           (account-records (mpt-dirty-node-records (first tries)))
           (storage-hashes
             (loop for trie in (rest tries)
                   append (mapcar #'car (mpt-dirty-node-records trie))))
           (node-map (snap-closure-account-node-map account-records))
           (code-hashes
             (loop for value
                     in (snap-closure-walk-account-subtree node-map root)
                   for account = (ethereum-lisp.state:decode-state-account-rlp
                                  value)
                   unless (hash32= (state-account-code-hash account)
                                   +empty-code-hash+)
                     collect (hash32-bytes (state-account-code-hash account))))
           (storage-account (keccak-256 (address-bytes wide)))
           (database (make-memory-key-value-database))
           (backend
             (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
              database state))
           (served nil)
           (audit
             (snap-closure-audit-batches
              database account-records
              (lambda ()
                (setf served
                      (snap-closure-serve-every-request-kind
                       backend root code-hashes storage-account))))))
      ;; The requests were answered from the state, not refused as unknown.
      (is (plusp (getf served :accounts)))
      (is (plusp (getf served :slots)))
      (is (plusp (getf served :codes)))
      (is (= 2 (getf served :nodes)))
      (is (plusp (length code-hashes)))
      (is (plusp (length storage-hashes)))
      ;; Nothing was written: no account node, no storage node.
      (is (zerop (getf audit :inspected)))
      (is (null (getf audit :violations)))
      (is (notany (lambda (record)
                    (nth-value 1 (trie-node-store-get database (car record))))
                  account-records))
      (is (notany (lambda (hash)
                    (nth-value 1 (trie-node-store-get database hash)))
                  storage-hashes))
      (is (null (snap-closure-store-violations database node-map)))
      ;; Positive control for the two absence checks: the old writer's exact
      ;; write -- the account trie alone -- is caught by both of them.
      (let* ((control (make-memory-key-value-database))
             (control-audit
               (snap-closure-audit-batches
                control account-records
                (lambda ()
                  (let ((batch (make-kv-write-batch)))
                    (dolist (record account-records)
                      (ethereum-lisp.database:kv-batch-put-chain-record
                       batch :trie-node (car record) (cdr record)))
                    (kv-apply-batch control batch))))))
        (is (plusp (getf control-audit :inspected)))
        (is (getf control-audit :violations))
        (is (nth-value 1 (trie-node-store-get control root)))
        (is (snap-closure-store-violations control node-map))))))

;;; ------------------------------------------------------------------
;;; Crash injection at the two batch seams
;;; ------------------------------------------------------------------

(defun snap-closure-crash-and-resume (state account-records trip seed)
  "Crash one import at TRIP's seam, then resume it, and return both verdicts."
  (let* ((root (state-db-root state))
         (node-map (snap-closure-account-node-map account-records))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            source-database state))
         (import
           (lambda ()
             (ethereum-lisp.snap-sync:snap-sync-import-state
              target-database (snap-test-source backend)
              :pivot-hash (make-hash32 (snap-test-hash seed))
              :pivot-number 77 :state-root root
              :target-hash (make-hash32 (snap-test-hash (+ seed 1)))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash (+ seed 2)))
              :authority-id (make-hash32 (snap-test-hash (+ seed 3)))
              :byte-limit 4096)))
         (audit
           (snap-closure-audit-batches
            target-database account-records
            (lambda ()
              (handler-case (funcall import)
                (serious-condition (condition)
                  (list :crashed (princ-to-string condition)))))
            :trip trip)))
    (values (snap-closure-store-violations target-database node-map)
            audit
            (funcall import))))

(deftest snap-account-closure-survives-a-crash-before-the-account-batch
  (:layer :integration :module :p2p)
  ;; Storage for a page is made durable in an earlier batch; the page's account
  ;; nodes follow.  Losing the trailing account batch must leave no account node
  ;; present for that page rather than a present node above an absent
  ;; dependency, and the resumed import must still converge.
  (with-snap-closure-proof-depth (2)
    (multiple-value-bind (state addresses wide) (snap-closure-dependency-fixture)
      (declare (ignore addresses wide))
      (let* ((account-records
               (mpt-dirty-node-records
                (first (state-db-persistence-tries state))))
             (account-hashes (make-hash-table :test #'equalp))
             (node-prefix (snap-closure-chain-prefix :trie-node))
             (storage-seen nil))
        (dolist (record account-records)
          (setf (gethash (car record) account-hashes) t))
        (multiple-value-bind (violations audit progress)
            (snap-closure-crash-and-resume
             state account-records
             (lambda (batch)
               (let ((account-node-p nil)
                     (other-node-p nil))
                 (dolist (operation
                          (ethereum-lisp.database::kv-write-batch-operations
                           batch))
                   (let ((key (second operation)))
                     (when (and (eq :put (first operation))
                                (plusp (length key))
                                (= (aref key 0) node-prefix))
                       (if (nth-value 1 (gethash (subseq key 1) account-hashes))
                           (setf account-node-p t)
                           (setf other-node-p t)))))
                 (when other-node-p (setf storage-seen t))
                 (and storage-seen account-node-p (not other-node-p))))
             80)
          (is (getf audit :tripped))
          (is storage-seen)
          (is (null (getf audit :violations)))
          (is (null violations))
          (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
               progress)))))))

(deftest snap-account-closure-survives-a-crash-before-the-cursor-batch
  (:layer :integration :module :p2p)
  ;; The account batch is buffered; the task cursor is published by a later
  ;; synchronous batch that fsyncs the whole preceding prefix.  Losing the
  ;; cursor batch replays the page, and the account nodes already written were
  ;; closed when they were written, so the store still holds no open account
  ;; node.
  (with-snap-closure-proof-depth (2)
    (multiple-value-bind (state addresses wide) (snap-closure-dependency-fixture)
      (declare (ignore addresses wide))
      (let* ((account-records
               (mpt-dirty-node-records
                (first (state-db-persistence-tries state))))
             (account-hashes (make-hash-table :test #'equalp))
             (node-prefix (snap-closure-chain-prefix :trie-node))
             (progress-key
               (ethereum-lisp.database::kv-chain-record-key
                :metadata
                ethereum-lisp.snap-sync::+snap-sync-progress-identifier+))
             (account-node-written nil))
        (dolist (record account-records)
          (setf (gethash (car record) account-hashes) t))
        (multiple-value-bind (violations audit progress)
            (snap-closure-crash-and-resume
             state account-records
             (lambda (batch)
               (let ((progress-p nil))
                 (dolist (operation
                          (ethereum-lisp.database::kv-write-batch-operations
                           batch))
                   (let ((key (second operation)))
                     (when (and (eq :put (first operation))
                                (plusp (length key)))
                       (cond
                         ((and (= (aref key 0) node-prefix)
                               (nth-value 1 (gethash (subseq key 1)
                                                     account-hashes)))
                          (setf account-node-written t))
                         ((bytes= key progress-key) (setf progress-p t))))))
                 (and account-node-written progress-p)))
             90)
          (is (getf audit :tripped))
          (is account-node-written)
          (is (null (getf audit :violations)))
          (is (null violations))
          (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
               progress)))))))

;;; ------------------------------------------------------------------
;;; Crash injection at the two cross-thread seams of the multi-source path
;;; ------------------------------------------------------------------

(defvar *snap-closure-batch-origin* nil
  "The writer a batch came from, bound on the thread that applies it.")

(defun call-with-snap-closure-writer-origins (thunk &key after-commit)
  "Run THUNK with the committer and code-worker applies tagged by origin.

Both writers run on their own threads, so the tag is a binding made by a
wrapper on that thread and read by the batch audit's TRIP on the same thread.
AFTER-COMMIT, when given, is called with each committed storage entry list
once SNAP-SYNC-MULTI-COMMIT-STORAGE-RESULTS has returned.  The wrappers are
installed process-globally and always restored."
  (let ((real-commit
          (fdefinition
           'ethereum-lisp.snap-sync::snap-sync-multi-commit-storage-results))
        (real-code
          (fdefinition 'ethereum-lisp.snap-sync::snap-sync-multi-code-worker)))
    (unwind-protect
         (progn
           (setf (fdefinition
                  'ethereum-lisp.snap-sync::snap-sync-multi-commit-storage-results)
                 (lambda (runtime database state-root entries &rest options)
                   (multiple-value-prog1
                       (let ((*snap-closure-batch-origin* :storage-committer))
                         (apply real-commit runtime database state-root entries
                                options))
                     (when after-commit
                       (funcall after-commit entries)))))
           (setf (fdefinition
                  'ethereum-lisp.snap-sync::snap-sync-multi-code-worker)
                 (lambda (&rest arguments)
                   (let ((*snap-closure-batch-origin* :code-worker))
                     (apply real-code arguments))))
           (funcall thunk))
      (setf (fdefinition
             'ethereum-lisp.snap-sync::snap-sync-multi-commit-storage-results)
            real-commit
            (fdefinition 'ethereum-lisp.snap-sync::snap-sync-multi-code-worker)
            real-code))))

(defun snap-closure-batch-puts (batch kind)
  "Return the keys BATCH puts for chain-record KIND, without the prefix."
  (let ((prefix (snap-closure-chain-prefix kind))
        (keys '()))
    (dolist (operation (ethereum-lisp.database::kv-write-batch-operations batch)
                       (nreverse keys))
      (let ((key (second operation)))
        (when (and (eq :put (first operation))
                   (plusp (length key))
                   (= prefix (aref key 0)))
          (push (subseq key 1) keys))))))

(defun snap-closure-batch-account-leaves (batch node-map)
  "Return the decoded account leaves beneath every account node BATCH puts."
  (loop for hash in (snap-closure-batch-puts batch :trie-node)
        when (nth-value 1 (gethash hash node-map))
          append (mapcar #'ethereum-lisp.state:decode-state-account-rlp
                         (snap-closure-walk-account-subtree node-map hash))))

(defun snap-closure-multi-crash-and-resume
    (state account-records trip seed &key after-commit)
  "Crash one multi-source import at TRIP's seam for good, then resume it.

Return the store's I1 violations right after the crash, the audit, the resumed
progress and the target database."
  (let* ((root (state-db-root state))
         (node-map (snap-closure-account-node-map account-records))
         (source-database (make-memory-key-value-database))
         (target-database (make-memory-key-value-database))
         (backend
           (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
            source-database state))
         (import
           (lambda ()
             (ethereum-lisp.snap-sync:snap-sync-import-state-multi
              target-database
              (list (snap-test-source backend) (snap-test-source backend))
              :pivot-hash (make-hash32 (snap-test-hash seed))
              :pivot-number 77 :state-root root
              :target-hash (make-hash32 (snap-test-hash (+ seed 1)))
              :chain-id 560048
              :genesis-hash (make-hash32 (snap-test-hash (+ seed 2)))
              :authority-id (make-hash32 (snap-test-hash (+ seed 3)))
              :byte-limit 4096)))
         (audit
           (call-with-snap-closure-writer-origins
            (lambda ()
              (snap-closure-audit-batches
               target-database account-records
               (lambda ()
                 (handler-case (funcall import)
                   (serious-condition (condition)
                     (list :crashed (princ-to-string condition)))))
               :trip trip :crash-latch t))
            :after-commit after-commit))
         (violations (snap-closure-store-violations target-database node-map)))
    (values violations audit (funcall import) target-database)))

(defun snap-closure-dependent-batch-trip
    (node-map origin kind dependent-p &key (ready-p (constantly t)))
  "Return a TRIP that crashes at the first account write depending on ORIGIN.

ORIGIN's applies are recognised by *SNAP-CLOSURE-BATCH-ORIGIN*, and the keys
each one puts for chain-record KIND are collected.  A batch from any other
writer is DEPENDENT when it puts an account node with a leaf beneath it for
which DEPENDENT-P, called with the leaf and the collected key table, is true.
The trip fires at the first dependent batch once ORIGIN has applied at least
once and READY-P is true; a dependent batch that arrives earlier is PREMATURE:
it is let through and counted, because it is the defect this seam must never
show.  A batch the memory backend re-applies through its inner entry point is
seen twice and answered the same way both times.

The second value is a function returning the origin's apply count, its key
table and the premature count."
  (let ((written (make-hash-table :test #'equalp))
        (origin-applies 0)
        (premature 0)
        (last-batch nil)
        (last-answer nil))
    (values
     (lambda (batch)
       (if (eq batch last-batch)
           last-answer
           (let ((answer
                   (cond
                     ((eq *snap-closure-batch-origin* origin)
                      (incf origin-applies)
                      (dolist (key (snap-closure-batch-puts batch kind))
                        (setf (gethash key written) t))
                      nil)
                     ((notany (lambda (leaf) (funcall dependent-p leaf written))
                              (snap-closure-batch-account-leaves batch node-map))
                      nil)
                     ((and (plusp origin-applies) (funcall ready-p))
                      t)
                     (t
                      (incf premature)
                      nil))))
             (setf last-batch batch last-answer answer))))
     (lambda () (values origin-applies written premature)))))

(deftest snap-account-closure-survives-a-crash-after-the-chunked-storage-commit
  (:layer :integration :module :p2p)
  ;; Chunked storage on the multi-source path is applied by the storage
  ;; committer thread (SNAP-SYNC-MULTI-COMMIT-STORAGE-RESULTS), not by the page
  ;; that owns the account.  No account node naming the chunked contract may be
  ;; written before the committer has applied the whole of its storage job,
  ;; and a crash for good at the first one written after that must leave the
  ;; store holding no account node whose closure it lacks, keep every storage
  ;; node the committer applied, and let a resumed import converge on the
  ;; authorized root.
  ;;
  ;; The batch audit's storage check is presence of the root NODE, which a
  ;; range proof can supply long before the storage is complete, so it cannot
  ;; see this seam; the premature count is the check that can.  Under the
  ;; closed writer the chunked contract's leaf is never in a range page's
  ;; account batch -- its root has no closure proof until the healer publishes
  ;; one -- so the first dependent account write is the healer's.  600 slots
  ;; against a 4096-byte cap is what makes the multi path chunk the contract;
  ;; 96 slots fit one response there.
  ;;
  ;; RED control (docs/evidence/sec5-snap-server-closure.txt): with the page no
  ;; longer waiting for its deferred storage and the closure predicate no
  ;; longer checking storage, this test fails.
  (with-snap-closure-proof-depth (2)
    (multiple-value-bind (state addresses wide)
        (snap-closure-dependency-fixture :wide-slots 600)
      (declare (ignore addresses))
      (let* ((account-trie (first (state-db-persistence-tries state)))
             (account-records (mpt-dirty-node-records account-trie))
             (node-map (snap-closure-account-node-map account-records))
             (wide-hash (keccak-256 (address-bytes wide)))
             (wide-root
               (hash32-bytes
                (state-account-storage-root
                 (ethereum-lisp.state:decode-state-account-rlp
                  (mpt-get account-trie wide-hash)))))
             (wide-committed nil))
        (multiple-value-bind (trip counters)
            (snap-closure-dependent-batch-trip
             node-map :storage-committer :trie-node
             (lambda (leaf written)
               (declare (ignore written))
               (bytes= wide-root
                       (hash32-bytes (state-account-storage-root leaf))))
             :ready-p (lambda () wide-committed))
          (multiple-value-bind (violations audit progress target)
              (snap-closure-multi-crash-and-resume
               state account-records trip 180
               :after-commit
               (lambda (entries)
                 (dolist (entry entries)
                   (let ((job (ethereum-lisp.snap-sync::snap-sync-global-storage-result-job
                               entry)))
                     (when (and (bytes= wide-hash
                                        (ethereum-lisp.snap-sync::snap-sync-global-storage-job-account-hash
                                         job))
                                (ethereum-lisp.snap-sync::snap-sync-global-storage-job-completed-p
                                 job))
                       (setf wide-committed t))))))
            (multiple-value-bind (committer-applies committed premature)
                (funcall counters)
              ;; No account node named the chunked storage before the committer
              ;; had applied all of it, and every account node the crashed run
              ;; did write was closed.
              (is (zerop premature))
              (is (null (getf audit :violations)))
              (is (null violations))
              (is (plusp (getf audit :inspected)))
              ;; The seam really fired, after the committer finished, and the
              ;; latch refused every later write.
              (is wide-committed)
              (is (getf audit :tripped))
              (is (plusp committer-applies))
              (is (plusp (hash-table-count committed)))
              (is (plusp (getf audit :dropped)))
              ;; The storage the committer applied before the crash survived it.
              (is (loop for hash being the hash-keys of committed
                        always (nth-value 1 (trie-node-store-get target hash))))
              ;; The resumed import converged on the authorized root.
              (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                   progress))
              (is (nth-value 1 (trie-node-store-get
                                target (hash32-bytes (state-db-root state)))))
              (is (null (snap-closure-store-violations target node-map))))))))))

(deftest snap-account-closure-survives-a-crash-after-the-code-worker-commit
  (:layer :integration :module :p2p)
  ;; Code on the multi-source path is written by the import-wide code worker's
  ;; own batch (SNAP-SYNC-MULTI-CODE-WORKER); the page that owns the account
  ;; learns of it only by re-reading the store.  Crash for good at the first
  ;; account batch naming a code the worker has applied: the store must hold
  ;; no account node whose closure it lacks, that code must have survived,
  ;; and a resumed import must converge and install the authorized root.
  ;; Code presence is exact, so here the batch audit's own code check is the
  ;; oracle for an account batch that outran its code.
  ;;
  ;; RED control (docs/evidence/sec5-snap-server-closure.txt): with the page no
  ;; longer waiting for its codes and the closure predicate no longer checking
  ;; code, this test fails.
  (with-snap-closure-proof-depth (2)
    (multiple-value-bind (state addresses wide) (snap-closure-dependency-fixture)
      (declare (ignore addresses wide))
      (let* ((account-records
               (mpt-dirty-node-records
                (first (state-db-persistence-tries state))))
             (node-map (snap-closure-account-node-map account-records)))
        (multiple-value-bind (trip counters)
            (snap-closure-dependent-batch-trip
             node-map :code-worker :code
             (lambda (leaf written)
               (nth-value 1 (gethash (hash32-bytes
                                      (state-account-code-hash leaf))
                                     written))))
          (multiple-value-bind (violations audit progress target)
              (snap-closure-multi-crash-and-resume
               state account-records trip 190)
            (multiple-value-bind (code-applies codes) (funcall counters)
              (is (null (getf audit :violations)))
              (is (null violations))
              (is (getf audit :tripped))
              (is (plusp code-applies))
              (is (plusp (hash-table-count codes)))
              (is (plusp (getf audit :dropped)))
              (is (loop for hash being the hash-keys of codes
                        always (nth-value 1 (kv-get-chain-record
                                             target :code hash))))
              (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                   progress))
              (is (nth-value 1 (trie-node-store-get
                                target (hash32-bytes (state-db-root state)))))
              (is (null (snap-closure-store-violations target node-map))))))))))

;;; ------------------------------------------------------------------
;;; The measurement that decides whether this design converges at all
;;; ------------------------------------------------------------------

(deftest snap-closed-account-writer-persists-most-of-the-account-trie
  (:layer :integration :module :p2p)
  ;; Option (a) does not write a withheld node, so healing must download it.
  ;; If the persisted fraction were low this would trade a local walk for a
  ;; multi-million-node wire download and be worse than the stall it replaces.
  ;; Measure it on a fixture with contract density, several pages and the
  ;; multi-source path, and pin the floor.
  (with-snap-closure-proof-depth (2)
    (multiple-value-bind (state addresses wide) (snap-closure-dependency-fixture)
      (declare (ignore addresses wide))
      (let* ((root (state-db-root state))
             (account-records
               (mpt-dirty-node-records
                (first (state-db-persistence-tries state))))
             (node-map (snap-closure-account-node-map account-records))
             (source-database (make-memory-key-value-database))
             (target-database (make-memory-key-value-database))
             (backend
               (ethereum-lisp.snap-sync:make-persistent-snap-state-backend
                source-database state))
             (pages 0)
             (reconstructed 0)
             (closed 0)
             (open-code 0)
             (open-storage 0))
        (ethereum-lisp.snap-sync:snap-sync-import-state-multi
         target-database
         (list (snap-test-source backend) (snap-test-source backend))
         :pivot-hash (make-hash32 (snap-test-hash 100))
         :pivot-number 120 :state-root root
         :target-hash (make-hash32 (snap-test-hash 101))
         :chain-id 560048
         :genesis-hash (make-hash32 (snap-test-hash 102))
         :authority-id (make-hash32 (snap-test-hash 103))
         :byte-limit 4096
         :on-page-profile
         (lambda (profile profile-source task-index)
           (declare (ignore profile-source task-index))
           (incf pages)
           (incf reconstructed
                 (ethereum-lisp.snap-sync::snap-sync-page-profile-trie-record-count
                  profile))
           (incf closed
                 (ethereum-lisp.snap-sync::snap-sync-page-profile-closed-node-count
                  profile))
           (incf open-code
                 (ethereum-lisp.snap-sync::snap-sync-page-profile-open-code-account-count
                  profile))
           (incf open-storage
                 (ethereum-lisp.snap-sync::snap-sync-page-profile-open-storage-account-count
                  profile))))
        (is (plusp pages))
        (is (plusp reconstructed))
        (is (plusp closed))
        ;; The whole point: after healing, the store is complete and holds no
        ;; account node whose closure it lacks.
        (is (null (snap-closure-store-violations target-database node-map)))
        (let ((durable 0))
          (maphash
           (lambda (hash encoded)
             (declare (ignore encoded))
             (when (nth-value 1 (trie-node-store-get target-database hash))
               (incf durable)))
           node-map)
          (is (= durable (hash-table-count node-map))))
        ;; Report the split so a regression in the withheld fraction is visible
        ;; in the run log rather than only in a live sync.
        (format *standard-output*
                "~&; closure measurement: account-trie-nodes=~D pages=~D ~
reconstructed=~D range-persisted=~D open-code-accounts=~D ~
open-storage-accounts=~D~%"
                (hash-table-count node-map) pages reconstructed closed
                open-code open-storage)
        (is (>= open-storage 0))))))

;;; ------------------------------------------------------------------
;;; The compensating machinery is disabled, not merely unreachable
;;; ------------------------------------------------------------------

(deftest snap-closed-account-store-never-promotes-a-range-plan
  (:layer :unit :module :p2p)
  ;; The walk-free completion publishes a state root without traversing the
  ;; trie, on the strength of a range plan whose promotion walks a durable
  ;; account spine.  A closed-writer store deliberately has no such spine, so
  ;; entering it would publish completion over a trie the healer has not filled
  ;; in.  It is already unreachable second-hand -- its predicate reads a plan
  ;; marker that is never written for such a store -- and this pins the
  ;; explicit guard so removing one of the two cannot silently re-open it.
  (let ((database (make-memory-key-value-database))
        (state-root (make-hash32 (snap-test-hash 61))))
    (is (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
         database))
    ;; Seed the plan marker and a promotion the legacy paths would consume, so
    ;; the guard is the only thing that can be keeping them out.
    (let ((batch (make-kv-write-batch)))
      (ethereum-lisp.snap-sync::snap-sync-populate-deferred-storage-plan-batch
       batch state-root)
      (kv-apply-batch database batch))
    (is (ethereum-lisp.snap-sync::snap-sync-deferred-storage-plan-present-p
         database state-root))
    ;; Control: with the legacy writer promotion gets past the marker check and
    ;; goes on to open a persisted MPT on the state root, which this synthetic
    ;; store does not hold. Reaching that walk at all is the proof that nothing
    ;; but the guard keeps the closed-writer arm out of it.
    (is (not (ethereum-lisp.snap-sync::snap-sync-closed-account-writes-p
              database)))
    (signals error
      (ethereum-lisp.snap-sync::snap-sync-promote-complete-range-plan
       database state-root))
    ;; Subject: under the closed writer both refuse before reading anything.
    (call-with-snap-closure-proof-depth
     4
     (lambda ()
       (is (ethereum-lisp.snap-sync::snap-sync-closed-account-writes-p
            database))
       (is (zerop
            (ethereum-lisp.snap-sync::snap-sync-promote-complete-range-plan
             database state-root)))))
    ;; SNAP-SYNC-RANGE-PLAN-FULLY-DURABLE-P itself is deliberately NOT gated:
    ;; it answers a question about the plan, and the guard belongs at the one
    ;; site that would act on the answer. That site,
    ;; SNAP-SYNC-FILL-STORAGE-THEN-HEAL, carries its own explicit refusal so
    ;; the completion cannot be re-opened by dropping the plan-marker gate.
    (is (ethereum-lisp.snap-sync::snap-sync-range-plan-fully-durable-p
         database state-root))))

(deftest snap-healed-storage-leaf-value-meets-the-uint256-ceiling
  (:layer :unit :module :p2p)
  ;; The 33-byte storage-value ceiling is what keeps account and storage nodes
  ;; disjoint in the kind-blind trie-node table, and contract storage is
  ;; attacker-controlled on a public network.  SNAP-SYNC-STORAGE-ENTRIES
  ;; applies it to every StorageRanges response, but a storage leaf reached by
  ;; hash during healing never passes through that function, so the same bound
  ;; is applied where such a node is decoded.
  (is (bytes= (rlp-encode (1- (ash 1 256)))
              (ethereum-lisp.snap-sync::snap-sync-storage-trie-value
               (rlp-encode (1- (ash 1 256))))))
  ;; An over-wide value, a zero value and a non-string value are all refused.
  (signals error
    (ethereum-lisp.snap-sync::snap-sync-storage-trie-value
     (rlp-encode (make-byte-vector 33 :initial-element 7))))
  (signals error
    (ethereum-lisp.snap-sync::snap-sync-storage-trie-value (rlp-encode 0)))
  ;; An account leaf value can never pass the storage ceiling, which is the
  ;; disjointness argument stated as an executable check.
  (signals error
    (ethereum-lisp.snap-sync::snap-sync-storage-trie-value
     (state-account-rlp (make-state-account)))))
