(in-package #:ethereum-lisp.test)

;;;; The healer's local walk: its constant factor, not which nodes it walks.
;;;;
;;;; docs/evidence/sec5-heal-walk-throughput.txt records the measurements these
;;;; tests pin.  Nothing here changes the skip/descend decision, the closure
;;;; epoch or the completion predicate; every walk below is compared against
;;;; the same walk under the previous width rule, and the two must visit the
;;;; same nodes and report the same missing references.

(deftest snap-heal-local-read-width-survives-a-frontier-above-the-live-bound
  (:layer :unit :module :p2p)
  ;; Hoodi 3305307d walked a 909,342-work frontier. The live bound is
  ;; 131,072, so the expansion room was zero and the width used to be one.
  (let ((live ethereum-lisp.snap-sync::+snap-sync-heal-live-frontier-max-works+)
        (expansion
          ethereum-lisp.snap-sync::+snap-sync-heal-max-net-expansion-per-work+)
        (overflow
          ethereum-lisp.snap-sync::+snap-sync-heal-live-overflow-read-width+)
        (checkpoint-works
          ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-max-works+))
    (is (= 130 overflow))
    (is (= 130
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            909342 0 1024 262144)))
    ;; The bounded pipeline refill keeps the exact old rule; its own loop guard
    ;; is what hands a saturated generation back to the event loop.
    (is (= 1
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            909342 0 1024 262144 1)))
    ;; Progress still binds above the live bound.
    (is (= 24
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            909342 1000 1024 262144)))
    ;; Checkpoint room binds only where a checkpoint can be written: a
    ;; frontier above one durable checkpoint (8,192 works) never moves the
    ;; checkpoint forward, so its room would stay at one for the rest of the
    ;; walk -- the Hoodi 75b0b7a7 width of exactly one from the 262,144th
    ;; processed node on.  The parent rule returned 5 and 1 here.
    (is (= 130
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            909342 0 1024 5)))
    (is (= 130
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            451583 0 16384 1)))
    (is (= 1024
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            8193 0 1024 1)))
    ;; Inside the checkpoint region the room binds exactly as before, so a
    ;; frontier that drains there still checkpoints on schedule.
    (is (= 5
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            8192 0 1024 5)))
    (is (= 1
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            5000 0 1024 1)))
    (is (= 5
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            100 0 2048 5)))
    ;; The bounded refill keeps its floor of one wherever the room is one.
    (is (= 1
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            909342 0 1024 1 1)))
    ;; The durable checkpoint region is untouched.
    (is (= 130
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            1 0 2048 2048)))
    (is (= 69
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            3800 0 296 2048)))
    (is (= 1921
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            10000 0 8192 8192)))
    ;; One batch overshoots the live bound by at most one durable checkpoint's
    ;; worth of works, and never shrinks below the overflow width there.
    (loop for stack-count from (- live 20000) to (+ live 20000) by 7
          for width =
            (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
             stack-count 0 4096 262144)
          do (is (<= (+ stack-count (* expansion width))
                     (+ (max stack-count live) checkpoint-works)))
             (is (>= width overflow)))
    (signals error
      (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
       909342 0 1024 262144 0))
    (signals error
      (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
       909342 0 1024 262144 (1+ overflow)))))

(defun snap-heal-walk-shared-subtree-trie (root-children)
  "Return (VALUES ROOT RECORDS MISSING) for a trie of shared subtrees.

Every depth-one child in 1..ROOT-CHILDREN names the same 16-ary subtree whose
depth-five leaves all hold one account, so a handful of stored nodes is walked
ROOT-CHILDREN x 69,905 times.  That is a real trie: its keys differ only in
their first five nibbles and share one suffix and value.  The depth-one
children at nibbles 0 and 15 are leaves that are never stored, so the first
local batch finds missing work whichever end of the branch it pops first, and
every post-order sentinel after it is blocked, which is how the Hoodi frontier
grew past its live bound."
  (let* ((account
           (state-account-rlp
            (make-state-account :nonce 3 :balance 424242)))
         (records '())
         (child
           (let ((leaf
                   (rlp-encode
                    (make-rlp-list
                     (ethereum-lisp.trie.encoding:hex-prefix-encode
                      (make-array 59 :initial-element 7) :terminator t)
                     account))))
             (push (cons (keccak-256 leaf) leaf) records)
             (keccak-256 leaf))))
    (loop repeat 4
          do (let ((branch
                     (rlp-encode
                      (apply #'make-rlp-list
                             (append (loop repeat 16 collect child)
                                     (list (make-byte-vector 0)))))))
               (setf child (keccak-256 branch))
               (push (cons child branch) records)))
    (let* ((missing
             (loop for balance in '(1 2)
                   collect
                   (keccak-256
                    (rlp-encode
                     (make-rlp-list
                      (ethereum-lisp.trie.encoding:hex-prefix-encode
                       (make-array 63 :initial-element balance)
                       :terminator t)
                      (state-account-rlp
                       (make-state-account :nonce 1 :balance balance)))))))
           (root
             (rlp-encode
              (apply #'make-rlp-list
                     (append
                      (loop for index below 16
                            collect
                            (cond
                              ((= index 0) (first missing))
                              ((= index 15) (second missing))
                              ((<= 1 index root-children) child)
                              (t (make-byte-vector 0))))
                      (list (make-byte-vector 0)))))))
      (push (cons (keccak-256 root) root) records)
      (values (keccak-256 root) records missing))))

#+sbcl
(defun snap-heal-walk-run (database root seed)
  "Walk ROOT from DATABASE until the healer asks a peer for missing nodes.

Return a plist of the walk's progress counters, the frontier it reached, the
local read width it kept while above the live bound, and the missing
references it requested."
  (let* ((live ethereum-lisp.snap-sync::+snap-sync-heal-live-frontier-max-works+)
         (requested '())
         (snapshots '())
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "Heal-walk fixture requested an account range"))
            :storage-ranges
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "Heal-walk fixture requested a storage range"))
            :bytecodes
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "Heal-walk fixture requested bytecode"))
            :trie-nodes
            (lambda (request)
              (push request requested)
              (error "Heal-walk fixture finished its local walk"))))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash (make-hash32 (snap-test-hash seed))
            :pivot-number 6090 :state-root (make-hash32 root)
            :partial-root +empty-trie-hash+
            :target-hash (make-hash32 (snap-test-hash (+ seed 1)))
            :chain-id 560048
            :genesis-hash (make-hash32 (snap-test-hash (+ seed 2)))
            :authority-id (make-hash32 (snap-test-hash (+ seed 3)))
            :completed-p nil :complete-node-scheme-p t
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 1 :completed-p t))))
    (signals error
      (ethereum-lisp.snap-sync::snap-sync-heal-state
       database (list source) progress (* 2 1024 1024)
       :on-heal-progress
       (lambda (snapshot) (push snapshot snapshots))))
    (setf snapshots (nreverse snapshots))
    (let ((above
            (remove-if-not
             (lambda (snapshot)
               (> (ethereum-lisp.snap-sync:snap-sync-heal-progress-frontier-works
                   snapshot)
                  live))
             snapshots))
          (last-snapshot (car (last snapshots))))
      (flet ((field (reader snapshot) (funcall reader snapshot)))
        (list
         :processed
         (field #'ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
                last-snapshot)
         :reused
         (field #'ethereum-lisp.snap-sync:snap-sync-heal-progress-reused-nodes
                last-snapshot)
         :skipped
         (field #'ethereum-lisp.snap-sync:snap-sync-heal-progress-skipped-subtrees
                last-snapshot)
         :max-frontier
         (reduce #'max snapshots
                 :key #'ethereum-lisp.snap-sync:snap-sync-heal-progress-frontier-works)
         :above-snapshots (length above)
         :above-batches
         (and above
              (- (ethereum-lisp.snap-sync:snap-sync-heal-progress-local-read-batches
                  (car (last above)))
                 (ethereum-lisp.snap-sync:snap-sync-heal-progress-local-read-batches
                  (first above))))
         :above-works
         (and above
              (- (ethereum-lisp.snap-sync:snap-sync-heal-progress-local-read-works
                  (car (last above)))
                 (ethereum-lisp.snap-sync:snap-sync-heal-progress-local-read-works
                  (first above))))
         :requested
         (sort
          (loop for request in requested
                append
                (loop for path-set
                        in (ethereum-lisp.snap:snap-get-trie-nodes-paths request)
                      collect (format nil "~{~A~^/~}"
                                      (mapcar #'bytes-to-hex
                                              (if (listp path-set)
                                                  path-set
                                                  (list path-set))))))
          #'string<))))))

#+sbcl
(deftest snap-heal-local-walk-keeps-wide-reads-above-the-live-frontier-bound
  (:layer :integration :module :p2p)
  ;; A local walk whose frontier passes 131,072 works while missing work is
  ;; pending, over a real on-disk RocksDB store in which every node is marked
  ;; incomplete: the mode the 3305307d Hoodi run was in.  The control arm
  ;; forces the previous width rule (a floor of one) through the shipped
  ;; limiter.  Both arms must walk the same nodes and request the same
  ;; missing references; only the batching may differ.
  (multiple-value-bind (root records missing)
      (snap-heal-walk-shared-subtree-trie 3)
    (declare (ignore missing))
    (let* ((limit-name
             'ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit)
           (real-limit (fdefinition limit-name))
           (results '()))
      (unwind-protect
           (dolist (arm '(:control :subject))
             (let ((path
                     (merge-pathnames
                      (make-pathname
                       :directory
                       `(:relative
                         ,(format nil "ethereum-lisp-heal-walk-~(~A~)-~A"
                                  arm (gensym))))
                      #P"/private/tmp/")))
               (setf (fdefinition limit-name)
                     (if (eq arm :control)
                         (lambda (stack missing-count missing-limit
                                  checkpoint-room &rest ignored)
                           (declare (ignore ignored))
                           (funcall real-limit stack missing-count
                                    missing-limit checkpoint-room 1))
                         real-limit))
               (unwind-protect
                    (let ((database (make-rocksdb-key-value-database path)))
                      (unwind-protect
                           (progn
                             (is
                              (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
                               database))
                             (let ((batch (make-kv-write-batch)))
                               (ethereum-lisp.snap-sync::snap-sync-populate-verified-trie-records-batch
                                database batch records)
                               (ethereum-lisp.snap-sync::snap-sync-populate-incomplete-records-batch
                                batch (mapcar #'car records))
                               (kv-apply-batch database batch))
                             (push (cons arm
                                         (snap-heal-walk-run database root 250))
                                   results))
                        (close-rocksdb-key-value-database database)))
                 (setf (fdefinition limit-name) real-limit)
                 (when (probe-file path)
                   (uiop:delete-directory-tree path :validate t)))))
        (setf (fdefinition limit-name) real-limit))
      (let ((control (cdr (assoc :control results)))
            (subject (cdr (assoc :subject results)))
            (live
              ethereum-lisp.snap-sync::+snap-sync-heal-live-frontier-max-works+))
        ;; The fixture really does reach the regime under test, in both arms.
        (dolist (run (list control subject))
          (is (> (getf run :max-frontier) live))
          (is (>= (getf run :above-snapshots) 8))
          (is (plusp (getf run :above-batches)))
          (is (= 2 (length (getf run :requested)))))
        ;; Same walk: which nodes are visited, reused and skipped, and which
        ;; references go to a peer, do not depend on the batch width.
        (dolist (key '(:processed :reused :skipped :requested))
          (is (equal (getf control key) (getf subject key))))
        (is (> (getf subject :processed) 200000))
        ;; RED arm: the old rule reads one work per batch above the bound.
        (is (= (getf control :above-batches) (getf control :above-works)))
        ;; Subject: the batch keeps the overflow width there instead.
        (is (>= (/ (getf subject :above-works) (getf subject :above-batches))
                64))
        (is (< (* 64 (getf subject :above-batches))
               (getf control :above-batches)))
        ;; The overshoot the wider batch buys is bounded, not merely small.
        (is (<= (getf subject :max-frontier)
                (+ (getf control :max-frontier)
                   ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-max-works+)))))))

(defun snap-heal-walk-reference-short-node-path (path compact)
  "The short-node path exactly as the healer derived it before it was inlined."
  (multiple-value-bind (segment leaf-p)
      (ethereum-lisp.trie.encoding:hex-prefix-decode compact)
    (let ((segment
            (if (and leaf-p
                     (ethereum-lisp.trie.encoding:has-terminator-p segment))
                (subseq segment 0 (1- (length segment)))
                segment)))
      (values (concatenate 'vector path segment) leaf-p))))

(deftest snap-heal-walk-per-node-encoders-match-their-generic-forms
  (:layer :unit :module :p2p)
  ;; The per-node helpers replace generic sequence code with typed octet
  ;; copies. Each must produce exactly what the generic form produced, now as
  ;; an octet vector, for every input the walk can present.
  (let ((state (sb-ext:seed-random-state 20260923))
        (checked 0))
    (flet ((random-bytes (count)
             (let ((bytes (make-byte-vector count)))
               (dotimes (index count bytes)
                 (setf (aref bytes index) (random 256 state)))))
           (random-path (count)
             (let ((path (make-byte-vector count)))
               (dotimes (index count path)
                 (setf (aref path index) (random 16 state))))))
      ;; Every hex-prefix flag byte, including the flags a malformed peer node
      ;; can carry, against every tail length a 32-byte key allows.
      (dotimes (first-byte 256)
        (loop for tail-length from 0 to 32
              for compact = (concatenate 'byte-vector
                                         (vector first-byte)
                                         (random-bytes tail-length))
              for path = (random-path (random 8 state))
              do (multiple-value-bind (expected expected-leaf-p)
                     (snap-heal-walk-reference-short-node-path path compact)
                   (multiple-value-bind (actual actual-leaf-p)
                       (ethereum-lisp.snap-sync::snap-sync-heal-short-node-path
                        path compact)
                     (is (typep actual 'byte-vector))
                     (is (equalp expected actual))
                     (is (eq expected-leaf-p actual-leaf-p))
                     (incf checked)))))
      (is (= (* 256 33) checked))
      ;; RED arm: the comparison can fail. Flipping the odd-length flag bit
      ;; changes the decoded nibbles.
      (let ((compact (make-array 3 :element-type '(unsigned-byte 8)
                                   :initial-contents '(#x3a #xbc #xde))))
        (is (not (equalp
                  (snap-heal-walk-reference-short-node-path #() compact)
                  (ethereum-lisp.snap-sync::snap-sync-heal-short-node-path
                   #() (make-array 3 :element-type '(unsigned-byte 8)
                                     :initial-contents '(#x2a #xbc #xde)))))))
      (dotimes (index 16)
        (let* ((path (random-path (random 64 state)))
               (child (ethereum-lisp.snap-sync::snap-sync-heal-child-path
                       path index)))
          (is (typep child 'byte-vector))
          (is (equalp (concatenate 'vector path (vector index)) child))))
      (let ((reference (random-bytes 32)))
        (dolist (entry
                 (list
                  (cons ethereum-lisp.snap-sync::+snap-sync-incomplete-node-identifier-prefix+
                        (ethereum-lisp.snap-sync::snap-sync-incomplete-node-identifier
                         reference))
                  (cons ethereum-lisp.snap-sync::+snap-sync-healed-subtree-identifier-prefix+
                        (ethereum-lisp.snap-sync::snap-sync-healed-subtree-identifier
                         reference :account))
                  (cons ethereum-lisp.snap-sync::+snap-sync-healed-storage-subtree-identifier-prefix+
                        (ethereum-lisp.snap-sync::snap-sync-healed-subtree-identifier
                         reference :storage))
                  (cons ethereum-lisp.snap-sync::+snap-sync-healed-storage-root-identifier-prefix+
                        (ethereum-lisp.snap-sync::snap-sync-healed-subtree-identifier
                         reference :storage-root))
                  (cons ethereum-lisp.snap-sync::+snap-sync-account-subtree-dependencies-identifier-prefix+
                        (ethereum-lisp.snap-sync::snap-sync-account-subtree-dependencies-identifier
                         reference))))
          (is (typep (cdr entry) 'byte-vector))
          (is (equalp (concatenate 'vector (car entry) reference) (cdr entry))))
        ;; The record key encoder is shared by every table; each identifier
        ;; shape it accepts must encode exactly as the generic concatenation.
        (dolist (identifier (list reference
                                  (coerce reference 'simple-vector)
                                  (make-byte-vector 0)
                                  "snap-state-heal-checkpoint"
                                  6202))
          (dolist (kind '(:trie-node :metadata))
            (is (equalp
                 (concat-bytes
                  (vector (ethereum-lisp.database::kv-chain-record-kind-prefix
                           kind))
                  (ethereum-lisp.database::kv-chain-record-identifier-bytes
                   identifier))
                 (ethereum-lisp.database::kv-chain-record-key
                  kind identifier)))))
        ;; Node-hash tables keep EQUALP semantics under the cheaper hash.
        (let ((table
                (ethereum-lisp.snap-sync::snap-sync-make-node-hash-table))
              (hashes (loop repeat 512 collect (random-bytes 32))))
          (dolist (hash hashes)
            (setf (gethash hash table) (copy-seq hash)))
          (is (= 512 (hash-table-count table)))
          (dolist (hash hashes)
            (is (equalp hash (gethash (copy-seq hash) table))))
          (is (null (nth-value 1 (gethash (random-bytes 32) table))))
          (is (= (ethereum-lisp.snap-sync::snap-sync-node-hash-key-hash
                  reference)
                 (ethereum-lisp.snap-sync::snap-sync-node-hash-key-hash
                  (copy-seq reference)))))))))

;;; ------------------------------------------------------------------
;;; Post-order sentinels no longer close a local read batch
;;; ------------------------------------------------------------------

(defun snap-heal-sentinel-marked-state (accounts slots)
  "Return (VALUES ROOT RECORDS CHILDREN) for a state whose storage is marked.

ACCOUNTS accounts each own SLOTS storage slots.  RECORDS are every
hash-addressed account and storage trie node.  CHILDREN maps a node hash to
the hashes the healer must resolve before that node's marker may go: its
hash-addressed trie children and, for an account leaf, its storage root."
  (let ((state (make-state-db)))
    (loop for index from 1 to accounts
          for address = (snap-test-address-from-integer (+ 7000 index))
          do (state-db-set-account
              state address
              (make-state-account :nonce index :balance (+ 500000 index)))
             (loop for slot from 1 to slots
                   do (state-db-set-storage
                       state address
                       (make-hash32
                        (snap-test-index-hash (+ (* index 4096) slot)))
                       (+ (* index 100000) slot))))
    (let* ((root (hash32-bytes (state-db-root state)))
           (tries (state-db-persistence-tries state))
           (encodings (make-hash-table :test #'equalp))
           (account-nodes (make-hash-table :test #'equalp))
           (children (make-hash-table :test #'equalp)))
      (loop for trie in tries
            for account-trie-p = t then nil
            do (dolist (record (mpt-dirty-node-records trie))
                 (when (= 32 (length (car record)))
                   (setf (gethash (car record) encodings) (cdr record))
                   (when account-trie-p
                     (setf (gethash (car record) account-nodes) t)))))
      (flet ((hash-child-p (reference)
               (and (byte-vector-p reference) (= 32 (length reference)))))
        (maphash
         (lambda (hash encoded)
           (let ((items (rlp-list-items
                         (rlp-decode-one encoded :max-list-items 17))))
             (setf (gethash hash children)
                   (cond
                     ((= 17 (length items))
                      (remove-if-not #'hash-child-p (subseq items 0 16)))
                     ((not (logbitp 5 (aref (first items) 0)))
                      (and (hash-child-p (second items))
                           (list (second items))))
                     ((gethash hash account-nodes)
                      (let ((storage-root
                              (state-account-storage-root
                               (decode-state-account-rlp (second items)))))
                        (unless (hash32= storage-root +empty-trie-hash+)
                          (list (hash32-bytes storage-root)))))
                     (t '())))))
         encodings))
      (values root
              (loop for hash being the hash-keys of encodings
                      using (hash-value encoded)
                    collect (cons hash encoded))
              children))))

(defun snap-heal-sentinel-run (root records children)
  "Heal the fully marked RECORDS from ROOT through the shipped healer.

Every node is present and carries its incomplete marker, so the walk is
purely local and must complete without asking the source for anything.
Return a plist of the healer's counters, the order in which markers were
deleted, the post-order violations that order contains against CHILDREN,
and the store's final entries."
  (let* ((database (make-memory-key-value-database))
         (deleted (make-hash-table :test #'equalp))
         (deletion-order '())
         (violations 0)
         (published 0)
         (early-publications 0)
         (snapshots '())
         (delete-name
           'ethereum-lisp.snap-sync::snap-sync-delete-incomplete-node-batch)
         (publish-name
           'ethereum-lisp.snap-sync::snap-sync-populate-healed-subtree-batch)
         (real-delete (fdefinition delete-name))
         (real-publish (fdefinition publish-name))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "Sentinel fixture requested an account range"))
            :storage-ranges
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "Sentinel fixture requested a storage range"))
            :bytecodes
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "Sentinel fixture requested bytecode"))
            :trie-nodes
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "Sentinel fixture requested a trie node"))))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash (make-hash32 (snap-test-hash 41))
            :pivot-number 6090 :state-root (make-hash32 root)
            :partial-root +empty-trie-hash+
            :target-hash (make-hash32 (snap-test-hash 42))
            :chain-id 560048
            :genesis-hash (make-hash32 (snap-test-hash 43))
            :authority-id (make-hash32 (snap-test-hash 44))
            :completed-p nil :complete-node-scheme-p t
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 1 :completed-p t))))
    (is (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
         database))
    (let ((batch (make-kv-write-batch)))
      (dolist (record records)
        (kv-batch-put-chain-record batch :trie-node (car record) (cdr record)))
      (ethereum-lisp.snap-sync::snap-sync-populate-incomplete-records-batch
       batch (mapcar #'car records))
      (kv-apply-batch database batch))
    (unwind-protect
         (progn
           ;; A marker may go only after every node it waits for is resolved.
           ;; Every node here is marked, so "resolved" is "its own marker went
           ;; first".
           (setf (fdefinition delete-name)
                 (lambda (batch reference)
                   (unless (every (lambda (child) (gethash child deleted))
                                  (gethash reference children))
                     (incf violations))
                   (setf (gethash (copy-seq reference) deleted) t)
                   (push (copy-seq reference) deletion-order)
                   (funcall real-delete batch reference))
                 (fdefinition publish-name)
                 (lambda (batch reference &rest rest)
                   (incf published)
                   (unless (gethash reference deleted)
                     (incf early-publications))
                   (apply real-publish batch reference rest)))
           (let ((outcome
                   (ethereum-lisp.snap-sync::snap-sync-heal-state
                    database (list source) progress (* 2 1024 1024)
                    :on-heal-progress
                    (lambda (snapshot) (push snapshot snapshots)))))
             (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                  outcome))))
      (setf (fdefinition delete-name) real-delete
            (fdefinition publish-name) real-publish))
    (let ((last-snapshot (first snapshots)))
      (list
       :processed
       (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
        last-snapshot)
       :reused
       (ethereum-lisp.snap-sync:snap-sync-heal-progress-reused-nodes
        last-snapshot)
       :skipped
       (ethereum-lisp.snap-sync:snap-sync-heal-progress-skipped-subtrees
        last-snapshot)
       :fetched
       (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
        last-snapshot)
       :batches
       (ethereum-lisp.snap-sync:snap-sync-heal-progress-local-read-batches
        last-snapshot)
       :works
       (ethereum-lisp.snap-sync:snap-sync-heal-progress-local-read-works
        last-snapshot)
       :max-frontier
       (reduce #'max snapshots
               :key
               #'ethereum-lisp.snap-sync:snap-sync-heal-progress-frontier-works)
       :deleted
       (sort (mapcar #'bytes-to-hex deletion-order) #'string<)
       :violations violations
       :published published
       :early-publications early-publications
       :marked-left
       (hash-table-count
        (ethereum-lisp.snap-sync::snap-sync-load-incomplete-nodes database))
       :entries
       (mapcar (lambda (entry)
                 (cons
                  (bytes-to-hex
                   (ethereum-lisp.database::kv-memory-entry-key entry))
                  (bytes-to-hex
                   (ethereum-lisp.database::kv-memory-entry-value entry))))
               (ethereum-lisp.database::kv-database-sorted-entries
                database))))))

(deftest snap-heal-restore-carried-completions-keeps-exposed-work-above
  (:layer :unit :module :p2p)
  (let* ((floor-list (list :f1 :f2))
         (stack (list* :new1 :new2 floor-list)))
    ;; CARRIED is most recent first; the sentinels go back in their original
    ;; order, directly on the floor, beneath everything integration pushed.
    (is (equal '(:new1 :new2 :s1 :s2 :f1 :f2)
               (ethereum-lisp.snap-sync::snap-sync-heal-restore-carried-completions
                stack floor-list (list :s2 :s1))))
    (is (equal '(:s1 :s2 :f1 :f2)
               (ethereum-lisp.snap-sync::snap-sync-heal-restore-carried-completions
                floor-list floor-list (list :s2 :s1))))
    (is (equal '(:new1 :s1)
               (ethereum-lisp.snap-sync::snap-sync-heal-restore-carried-completions
                (list :new1) nil (list :s1))))
    (let ((untouched (list :new1 :f1)))
      (is (eq untouched
              (ethereum-lisp.snap-sync::snap-sync-heal-restore-carried-completions
               untouched (cdr untouched) '()))))
    ;; A floor that is not a tail of the stack is a diverged frontier.
    (signals error
      (ethereum-lisp.snap-sync::snap-sync-heal-restore-carried-completions
       (list :new1 :f1) (list :f1) (list :s1)))))

(deftest snap-heal-local-read-batch-carries-post-order-sentinels
  (:layer :unit :module :p2p)
  ;; 64 accounts, each owning 40 storage slots, with every account and
  ;; storage trie node present AND marked incomplete -- the shape a partially
  ;; delivered range leaves and the one the Hoodi heal reports
  ;; (knownIncompleteNodes tracking processedNodes).  Nothing is missing, so
  ;; the walk is purely local and completes.
  ;;
  ;; The control arm is the previous rule (carry bound zero): a post-order
  ;; sentinel popped after the batch's first lookup closes the batch, so the
  ;; mean width is the fan-out of one node.  The subject carries the
  ;; sentinels.  Both must walk the same nodes, delete the same markers in
  ;; post-order, and leave byte-identical stores.
  (multiple-value-bind (root records children)
      (snap-heal-sentinel-marked-state 64 40)
    (let ((control
            (let ((ethereum-lisp.snap-sync::*snap-sync-heal-carried-completions-per-batch*
                    0))
              (snap-heal-sentinel-run root records children)))
          (subject (snap-heal-sentinel-run root records children)))
      (is (> (length records) 3000))
      (dolist (run (list control subject))
        (is (= (length records) (getf run :processed)))
        (is (= (length records) (length (getf run :deleted))))
        (is (zerop (getf run :marked-left)))
        (is (zerop (getf run :fetched)))
        ;; The ordering property, in both arms: no marker went while a node
        ;; it waits for was unresolved, and no subtree record was published
        ;; above a node whose marker was still there.
        (is (zerop (getf run :violations)))
        (is (plusp (getf run :published)))
        (is (zerop (getf run :early-publications))))
      (dolist (key '(:processed :reused :skipped :fetched :published
                     :deleted :entries))
        (is (equal (getf control key) (getf subject key))))
      ;; RED arm: the previous rule reads at the fan-out of one node.
      (is (< (/ (getf control :works) (getf control :batches)) 4))
      ;; Subject: batches fill across the carried sentinels.
      (is (>= (/ (getf subject :works) (getf subject :batches)) 16))
      (is (< (* 16 (getf subject :batches)) (getf control :batches)))
      ;; Carrying never takes the frontier past one durable checkpoint.
      (is (<= (getf subject :max-frontier)
              ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-max-works+)))))

(deftest snap-heal-carried-sentinels-wait-for-the-work-their-batch-exposes
  (:layer :unit :module :p2p)
  ;; RED arm for the ordering property.  Put the carried sentinels back ON TOP
  ;; of the work their own batch's integration exposed -- i.e. let a node's
  ;; completion run before its last children resolve -- and the same fixture
  ;; must report markers deleted above unresolved children.  The subject's
  ;; zero in SNAP-HEAL-LOCAL-READ-BATCH-CARRIES-POST-ORDER-SENTINELS is only
  ;; meaningful because this arm is not zero.
  (multiple-value-bind (root records children)
      (snap-heal-sentinel-marked-state 64 40)
    (let* ((name
             'ethereum-lisp.snap-sync::snap-sync-heal-restore-carried-completions)
           (real (fdefinition name))
           (early
             (unwind-protect
                  (progn
                    (setf (fdefinition name)
                          (lambda (stack batch-floor carried)
                            (declare (ignore batch-floor))
                            (revappend carried stack)))
                    (snap-heal-sentinel-run root records children))
               (setf (fdefinition name) real))))
      (is (plusp (getf early :violations)))
      ;; The misordered walk still "completes" and deletes every marker: the
      ;; violation is invisible to the counters, which is why the test reads
      ;; the order itself.
      (is (zerop (getf early :marked-left))))))

;;; ------------------------------------------------------------------
;;; Checkpoint room above a frontier that cannot be checkpointed
;;; ------------------------------------------------------------------

(defun snap-heal-walk-missing-leaves ()
  "Return the encodings of the two leaves SNAP-HEAL-WALK-SHARED-SUBTREE-TRIE
withholds, keyed by the hex of the compact path the healer requests."
  (loop for balance in '(1 2)
        for nibble in '(0 15)
        collect
        (cons (bytes-to-hex
               (ethereum-lisp.trie.encoding:hex-prefix-encode
                (vector nibble) :terminator nil))
              (rlp-encode
               (make-rlp-list
                (ethereum-lisp.trie.encoding:hex-prefix-encode
                 (make-array 63 :initial-element balance) :terminator t)
                (state-account-rlp
                 (make-state-account :nonce 1 :balance balance)))))))

#+sbcl
(defun snap-heal-walk-complete-run (root records missing)
  "Heal the shared-subtree trie to completion from a memory store.

The source serves exactly the two withheld leaves.  Return the heal's final
counters, its progress snapshots in order, how many times each marker was
deleted, and the store's final entries."
  (let* ((database (make-memory-key-value-database))
         (leaves (snap-heal-walk-missing-leaves))
         (snapshots '())
         (deletions (make-hash-table :test #'equal))
         (delete-name
           'ethereum-lisp.snap-sync::snap-sync-delete-incomplete-node-batch)
         (real-delete (fdefinition delete-name))
         (source
           (ethereum-lisp.snap-sync:make-snap-sync-source
            :account-range
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "Heal-walk fixture requested an account range"))
            :storage-ranges
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "Heal-walk fixture requested a storage range"))
            :bytecodes
            (lambda (&rest arguments)
              (declare (ignore arguments))
              (error "Heal-walk fixture requested bytecode"))
            :trie-nodes
            (lambda (request)
              (ethereum-lisp.snap:make-snap-trie-nodes
               (ethereum-lisp.snap:snap-get-trie-nodes-id request)
               (loop for path-set
                       in (ethereum-lisp.snap:snap-get-trie-nodes-paths request)
                     for path = (bytes-to-hex
                                 (if (listp path-set)
                                     (first path-set)
                                     path-set))
                     collect (or (cdr (assoc path leaves :test #'string=))
                                 (error "Heal-walk fixture was asked for ~A"
                                        path)))))))
         (progress
           (ethereum-lisp.snap-sync::snap-sync-make-progress
            :pivot-hash (make-hash32 (snap-test-hash 61))
            :pivot-number 6090 :state-root (make-hash32 root)
            :partial-root +empty-trie-hash+
            :target-hash (make-hash32 (snap-test-hash 62))
            :chain-id 560048
            :genesis-hash (make-hash32 (snap-test-hash 63))
            :authority-id (make-hash32 (snap-test-hash 64))
            :completed-p nil :complete-node-scheme-p t
            :tasks
            (ethereum-lisp.snap-sync::snap-sync-make-account-tasks
             :count 1 :completed-p t))))
    ;; The fixture's withheld hashes are exactly the leaves served here.
    (is (equalp (sort (mapcar #'bytes-to-hex missing) #'string<)
                (sort (mapcar (lambda (leaf) (bytes-to-hex (keccak-256 (cdr leaf))))
                              leaves)
                      #'string<)))
    (is (ethereum-lisp.snap-sync::snap-sync-enable-complete-node-scheme-p
         database))
    (let ((batch (make-kv-write-batch)))
      (ethereum-lisp.snap-sync::snap-sync-populate-verified-trie-records-batch
       database batch records)
      (ethereum-lisp.snap-sync::snap-sync-populate-incomplete-records-batch
       batch (mapcar #'car records))
      (kv-apply-batch database batch))
    (unwind-protect
         (progn
           (setf (fdefinition delete-name)
                 (lambda (batch reference)
                   (incf (gethash (bytes-to-hex reference) deletions 0))
                   (funcall real-delete batch reference)))
           (is (ethereum-lisp.snap-sync:snap-sync-progress-completed-p
                (ethereum-lisp.snap-sync::snap-sync-heal-state
                 database (list source) progress (* 2 1024 1024)
                 :on-heal-progress
                 (lambda (snapshot) (push snapshot snapshots))))))
      (setf (fdefinition delete-name) real-delete))
    (setf snapshots (nreverse snapshots))
    (let ((last-snapshot (car (last snapshots))))
      (list
       :processed
       (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
        last-snapshot)
       :reused
       (ethereum-lisp.snap-sync:snap-sync-heal-progress-reused-nodes
        last-snapshot)
       :skipped
       (ethereum-lisp.snap-sync:snap-sync-heal-progress-skipped-subtrees
        last-snapshot)
       :fetched
       (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
        last-snapshot)
       :snapshots snapshots
       :deletions
       (sort (loop for key being the hash-keys of deletions
                     using (hash-value count)
                   collect (cons key count))
             #'string< :key #'car)
       :marked-left
       (hash-table-count
        (ethereum-lisp.snap-sync::snap-sync-load-incomplete-nodes database))
       :entries
       (mapcar (lambda (entry)
                 (cons
                  (bytes-to-hex
                   (ethereum-lisp.database::kv-memory-entry-key entry))
                  (bytes-to-hex
                   (ethereum-lisp.database::kv-memory-entry-value entry))))
               (ethereum-lisp.database::kv-database-sorted-entries
                database))))))

(defun snap-heal-walk-width-after (snapshots processed-floor)
  "Return (VALUES BATCHES WORKS) read locally between the first snapshot at or
past PROCESSED-FLOOR and the last one taken before any node was fetched."
  (let* ((local
           (remove-if
            (lambda (snapshot)
              (plusp
               (ethereum-lisp.snap-sync:snap-sync-heal-progress-fetched-nodes
                snapshot)))
            snapshots))
         (start
           (find-if
            (lambda (snapshot)
              (>= (ethereum-lisp.snap-sync:snap-sync-heal-progress-processed-nodes
                   snapshot)
                  processed-floor))
            local))
         (end (car (last local))))
    (values
     (- (ethereum-lisp.snap-sync:snap-sync-heal-progress-local-read-batches end)
        (ethereum-lisp.snap-sync:snap-sync-heal-progress-local-read-batches start))
     (- (ethereum-lisp.snap-sync:snap-sync-heal-progress-local-read-works end)
        (ethereum-lisp.snap-sync:snap-sync-heal-progress-local-read-works start)))))

#+sbcl
(deftest snap-heal-checkpoint-room-does-not-bind-an-uncheckpointable-frontier
  (:layer :integration :module :p2p)
  ;; Four depth-one children share one 16-ary subtree, so 279,620 marked
  ;; nodes are walked while two withheld leaves are pending: every sentinel
  ;; is blocked and the frontier passes 131,072 works, the Hoodi shape.  No
  ;; heal checkpoint can be written above 8,192 works, so the checkpoint
  ;; never moves and, on the parent rule, its room is one from the 262,144th
  ;; processed node on: every later batch reads one node.  The control arm
  ;; restores that rule through the shipped limiter.  Both arms then fetch
  ;; the two leaves and complete; the walk, the markers deleted and the final
  ;; store must not depend on the width.
  (multiple-value-bind (root records missing)
      (snap-heal-walk-shared-subtree-trie 4)
    (let* ((limit-name
             'ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit)
           (real-limit (fdefinition limit-name))
           (interval
             ethereum-lisp.snap-sync::+snap-sync-heal-checkpoint-node-interval+)
           (window-start
             (+ interval
                ethereum-lisp.snap-sync::*snap-sync-heal-progress-node-interval*))
           (control
             (unwind-protect
                  (progn
                    (setf (fdefinition limit-name)
                          (lambda (stack missing-count missing-limit
                                   checkpoint-room &rest rest)
                            (min (apply real-limit stack missing-count
                                        missing-limit checkpoint-room rest)
                                 checkpoint-room)))
                    (snap-heal-walk-complete-run root records missing))
               (setf (fdefinition limit-name) real-limit)))
           (subject (snap-heal-walk-complete-run root records missing)))
      (dolist (run (list control subject))
        ;; The regime is reached: past the checkpoint interval, above the live
        ;; bound, with nothing fetched yet.
        (is (> (getf run :processed) (+ interval 8192)))
        (is (> (reduce #'max (getf run :snapshots)
                       :key #'ethereum-lisp.snap-sync:snap-sync-heal-progress-frontier-works)
               ethereum-lisp.snap-sync::+snap-sync-heal-live-frontier-max-works+))
        (is (= 2 (getf run :fetched)))
        (is (zerop (getf run :marked-left)))
        (is (plusp (length (getf run :deletions)))))
      (dolist (key '(:processed :reused :skipped :fetched :deletions :entries))
        (is (equal (getf control key) (getf subject key))))
      (multiple-value-bind (batches works)
          (snap-heal-walk-width-after (getf control :snapshots) window-start)
        ;; RED arm: the parent rule reads exactly one node per batch here.
        (is (> works 8192))
        (is (= batches works)))
      (multiple-value-bind (batches works)
          (snap-heal-walk-width-after (getf subject :snapshots) window-start)
        ;; Subject: the batch keeps its width for the whole walk.
        (is (> works 8192))
        (is (>= works (* 16 batches)))))))
