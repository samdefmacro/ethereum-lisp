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
    ;; Progress and checkpoint room still bind above the live bound.
    (is (= 24
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            909342 1000 1024 262144)))
    (is (= 5
           (ethereum-lisp.snap-sync::snap-sync-heal-local-read-limit
            909342 0 1024 5)))
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
