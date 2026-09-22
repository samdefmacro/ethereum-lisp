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

(defun snap-marker-census (database markers owners creators)
  "Attribute MARKERS by creating site and owning trie; judge each one."
  (let ((rows (make-hash-table :test #'equal))
        (memo (make-hash-table :test #'equalp))
        (classes (make-hash-table :test #'equalp)))
    (maphash
     (lambda (hash ignored)
       (declare (ignore ignored))
       (let* ((owner (gethash hash owners))
              (trie (cond ((null owner) :unreachable)
                          ((eq owner :account) :account)
                          (t (or (gethash (cdr owner) classes)
                                 (setf (gethash (cdr owner) classes)
                                       (snap-marker-storage-class
                                        database (cdr owner)))))))
              (site (or (gethash hash creators) :unknown))
              (verdict (if (snap-marker-closed-p database hash memo)
                           :stale :genuine))
              (key (list site trie verdict)))
         (incf (gethash key rows 0))))
     markers)
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
                           (byte-limit 30000) (seed 70))
  "Import STATE-ROOT into a fresh epoch-seven store and take the marker census.

With BEFORE, REBASE-AFTER-PAGES account pages are first downloaded under
BEFORE-ROOT and the progress is rebased: the live mid-range rebase."
  (let* ((target (make-memory-key-value-database))
         (at-heal nil)
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
                  :max-pages max-pages)
                 (ethereum-lisp.snap-sync:snap-sync-import-state
                  target (first (funcall sources-for state))
                  :pivot-hash pivot-hash :pivot-number number
                  :state-root root :target-hash pivot-hash
                  :chain-id 560048 :genesis-hash (funcall pivot 1)
                  :authority-id (funcall pivot 2) :byte-limit byte-limit
                  :max-pages max-pages))))
         (real-heal (fdefinition 'ethereum-lisp.snap-sync::snap-sync-heal-state)))
    (multiple-value-bind (final instrumentation)
        (call-with-snap-marker-instrumentation
         (lambda ()
           (unwind-protect
                (progn
                  (setf (fdefinition 'ethereum-lisp.snap-sync::snap-sync-heal-state)
                        (lambda (&rest arguments)
                          (unless at-heal
                            (setf at-heal (snap-marker-markers target)))
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
                   real-heal))))
      (let* ((owners (snap-marker-owners target state-root))
             (creators (getf instrumentation :creators))
             (at-end (snap-marker-markers target)))
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
              :at-heal-count (and at-heal (hash-table-count at-heal))
              :at-heal (and at-heal
                            (snap-marker-census target at-heal owners creators))
              :at-end-count (hash-table-count at-end)
              :at-end (snap-marker-census target at-end owners creators)
              :target target)))))
