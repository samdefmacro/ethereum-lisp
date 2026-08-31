(in-package #:ethereum-lisp.node-store.persistence)

(defun node-store-put-state-record
    (chain-store database batch hash identifier record-label code-sink)
  "Write HASH's state under its stored kind — a full :STATE snapshot for a
baseline, a :STATE-DIFF record for a diff — and drop the other kind's stale
record. Returns T when the batch changed."
  (let ((changed-p nil)
        (pending-nodes nil))
    (multiple-value-bind (trie-changed-p nodes)
        (chain-store-populate-state-trie-record-to-kv
         chain-store database batch hash identifier record-label code-sink)
      (when trie-changed-p
        (setf changed-p t))
      (setf pending-nodes nodes))
    (ecase (chain-store-state-record-kind
            chain-store (bytes-to-hex identifier))
      (:baseline
       (when (node-store-put-immutable-record
              database batch :state identifier
              (chain-store-state-record-rlp
               chain-store hash :code-sink code-sink)
              record-label)
         (setf changed-p t))
       (when (node-store-sync-chain-record
              database batch :state-diff identifier nil)
         (setf changed-p t)))
      (:diff
       (when (node-store-put-immutable-record
              database batch :state-diff identifier
              (chain-store-state-diff-record-rlp
               chain-store (bytes-to-hex identifier) :code-sink code-sink)
              record-label)
         (setf changed-p t))
       (when (node-store-sync-chain-record
              database batch :state identifier nil)
         (setf changed-p t)))
      (:trie
       (when (node-store-sync-chain-record
              database batch :state identifier nil)
         (setf changed-p t))
       (when (node-store-sync-chain-record
              database batch :state-diff identifier nil)
         (setf changed-p t))))
    (values changed-p pending-nodes)))

(defun node-store-installed-block-records-durable-p (store block)
  "Return true only for the explicit committed Engine candidate hint.

Absence from the direct provider's block overlay is not sufficient evidence:
a SNAP pivot is also read directly while its canonical state record still has
to be published.  The one-slot hint is installed only after an Engine
candidate's block and state batch commits, then consumed by forkchoice."
  (let ((hint (memory-chain-store-durable-engine-payload-hash store)))
    (and (chain-store-durable-state-provider-p store)
         hint
         (hash32= hint (block-hash block)))))

(defun node-store-installed-state-record-durable-p (store block)
  "Return true only when BLOCK has the committed Engine candidate hint."
  (node-store-installed-block-records-durable-p store block))

(defun node-store-put-immutable-record
    (database batch kind identifier value record-label)
  (multiple-value-bind (existing-value present-p)
      (kv-get-chain-record database kind identifier)
    (cond
      ((not present-p)
       (kv-batch-put-chain-record batch kind identifier value)
       t)
      ((bytes= existing-value value)
       nil)
      (t
       (block-validation-fail
        "~A conflicts with persisted ~A record"
        record-label kind)))))

(defun node-store-put-immutable-block-records
    (database batch block record-label &key allow-missing-committed-p)
  (let ((identifier (hash32-bytes (block-hash block)))
        (changed-p nil))
    (when (node-store-put-immutable-block-body-record
           database batch :block block record-label
           :allow-missing-committed-p allow-missing-committed-p)
      (setf changed-p t))
    (when (node-store-put-immutable-record
           database batch :header identifier
           (block-header-rlp (block-header block)) record-label)
      (setf changed-p t))
    (when (node-store-put-immutable-record
           database batch :receipt identifier
           (block-receipts-record-rlp block) record-label)
      (setf changed-p t))
    changed-p))

(defconstant +node-store-snap-skeleton-batch-limit+ 192)

(defun node-store-validate-snap-skeleton-block (block)
  (unless (typep block 'ethereum-block)
    (block-validation-fail "Snap skeleton contains a non-block"))
  (ethereum-lisp.execution:validate-block-body-commitments-before-execution
   (block-transactions block) (block-header block)
   :ommers (block-ommers block)
   :withdrawals (block-withdrawals block)
   :withdrawals-supplied-p (block-withdrawals-present-p block)
   :requests (block-requests block)
   :requests-supplied-p (block-requests-present-p block)
   :block-access-list (block-block-access-list block)
   :block-access-list-supplied-p (block-block-access-list-present-p block))
  (unless (= (length (block-transactions block))
             (length (block-receipts block)))
    (block-validation-fail
     "Snap skeleton block requires one receipt per transaction"))
  (unless (hash32=
           (block-header-receipts-root (block-header block))
           (ethereum-lisp.receipts:transaction-receipt-list-root
            (block-transactions block) (block-receipts block)))
    (block-validation-fail
     "Snap skeleton receipts do not match the header"))
  block)

(defun node-store-export-snap-skeleton-batch-to-kv
    (database blocks progress)
  "Persist one verified CL-target skeleton batch and its cursor atomically."
  (unless (and (listp blocks) blocks
               (<= (length blocks) +node-store-snap-skeleton-batch-limit+))
    (block-validation-fail
     "Snap skeleton batch must contain 1 to ~D blocks"
     +node-store-snap-skeleton-batch-limit+))
  (node-store-validate-snap-skeleton-progress database progress)
  (loop for previous = nil then block
        for block in blocks
        do (node-store-validate-snap-skeleton-block block)
           (when previous
             (unless (and
                      (= (block-header-number (block-header block))
                         (1+ (block-header-number (block-header previous))))
                      (hash32= (block-header-parent-hash (block-header block))
                               (block-hash previous)))
               (block-validation-fail
                "Snap skeleton batch is not hash-contiguous"))))
  (let ((first (first blocks))
        (last (car (last blocks))))
    (unless (and
             (= (block-header-number (block-header last))
                (node-store-snap-skeleton-progress-last-number progress))
             (hash32= (block-hash last)
                      (node-store-snap-skeleton-progress-last-hash progress)))
      (block-validation-fail
       "Snap skeleton batch does not match its progress cursor"))
    (multiple-value-bind (existing present-p)
        (node-store-read-snap-skeleton-progress database)
      (let ((expected-number
              (1+ (if present-p
                      (node-store-snap-skeleton-progress-last-number existing)
                      (node-store-snap-skeleton-progress-anchor-number progress))))
            (expected-parent
              (if present-p
                  (node-store-snap-skeleton-progress-last-hash existing)
                  (node-store-snap-skeleton-progress-anchor-hash progress))))
        (unless (and
                 (= expected-number
                    (block-header-number (block-header first)))
                 (hash32= expected-parent
                          (block-header-parent-hash (block-header first))))
          (block-validation-fail
           "Snap skeleton batch does not extend its durable cursor"))))
    (let ((batch (make-kv-write-batch))
          (changed-p nil))
      (dolist (block blocks)
        (when (node-store-put-immutable-block-records
               database batch block "Snap skeleton"
               :allow-missing-committed-p t)
          (setf changed-p t)))
      (when (node-store-populate-snap-skeleton-progress-batch
             database batch progress)
        (setf changed-p t))
      (kv-batch-put-chain-schema-version batch)
      (when changed-p (kv-apply-batch database batch))
      progress)))

(defun node-store-sync-chain-record
    (database batch kind identifier desired-value)
  (multiple-value-bind (existing-value present-p)
      (kv-get-chain-record database kind identifier)
    (cond
      ((and desired-value present-p
            (bytes= existing-value desired-value))
       nil)
      (desired-value
       (kv-batch-put-chain-record batch kind identifier desired-value)
       t)
      (present-p
       (kv-batch-delete-chain-record batch kind identifier)
       t)
      (t nil))))

(defun node-store-sync-canonical-hash (database batch store number)
  (let ((desired-hash (chain-store-canonical-hash store number)))
    (multiple-value-bind (existing-hash present-p)
        (kv-get-chain-canonical-hash database number)
      (cond
        ((and desired-hash present-p
              (bytes= existing-hash (hash32-bytes desired-hash)))
         nil)
        (desired-hash
         (kv-batch-put-chain-canonical-hash
          batch number (hash32-bytes desired-hash))
         t)
        (present-p
         (kv-batch-delete-chain-canonical-hash batch number)
         t)
        (t nil)))))

(defun node-store-sync-checkpoint (database batch checkpoint label)
  (let* ((hash (and checkpoint
                    (chain-store-checkpoint-block-hash checkpoint)))
         (desired-value (and hash (hash32-bytes hash))))
    (multiple-value-bind (existing-value present-p)
        (kv-get-chain-checkpoint database label)
      (cond
        ((and desired-value present-p
              (bytes= existing-value desired-value))
         nil)
        (desired-value
         (kv-batch-put-chain-checkpoint batch label desired-value)
         t)
        (present-p
         (kv-batch-delete-chain-checkpoint batch label)
         t)
        (t nil)))))

(defun node-store-transition-blocks (transition)
  (append
   (canonical-chain-transition-installed-blocks transition)
   (canonical-chain-transition-displaced-blocks transition)))

(defun node-store-unique-blocks (blocks)
  (let ((blocks-by-hash (make-hash-table :test 'equalp)))
    (dolist (block blocks)
      (unless (typep block 'ethereum-block)
        (block-validation-fail
         "Forkchoice transition contains a non-block entry"))
      (setf (gethash (hash32-to-hex (block-hash block)) blocks-by-hash)
            block))
    (sort
     (loop for block being the hash-values of blocks-by-hash collect block)
     #'<
     :key (lambda (block)
            (block-header-number (block-header block))))))

(defun node-store-database-head-number (database)
  (multiple-value-bind (identifier present-p)
      (kv-get-chain-checkpoint database :head)
    (when present-p
      (let ((head-hash (make-hash32 identifier)))
        (multiple-value-bind (record block-present-p)
            (kv-get-chain-record database :block identifier)
          (unless block-present-p
            (block-validation-fail
             "Persisted head checkpoint has no block record"))
          (let ((block
                  (chain-store-block-from-persisted-record
                   database identifier record "Persisted head checkpoint")))
            (unless (hash32= (block-hash block) head-hash)
              (block-validation-fail
               "Persisted head checkpoint block hash does not match"))
            (block-header-number (block-header block))))))))

(defun node-store-database-canonical-block
    (database number identifier)
  (let ((expected-hash (make-hash32 identifier)))
    (multiple-value-bind (record present-p)
        (kv-get-chain-record database :block identifier)
      (unless present-p
        (block-validation-fail
         "Persisted canonical height ~D has no block record" number))
      (let ((block
              (chain-store-block-from-persisted-record
               database identifier record "Persisted canonical block")))
        (unless (and (hash32= (block-hash block) expected-hash)
                     (= (block-header-number (block-header block)) number))
          (block-validation-fail
           "Persisted canonical block does not match height ~D" number))
        block))))

(defun node-store-canonical-difference (store database)
  "Return keyed canonical changes needed to advance DATABASE to STORE.

The walk stops at the first matching canonical ancestor and reads no database
range.  This also covers locally canonicalized blocks that predate a
same-head forkchoice call without reintroducing a full-store scan."
  (let* ((current-head-number (chain-store-head-number store))
         (database-head-number (node-store-database-head-number database))
         (numbers (make-hash-table :test 'eql))
         (blocks nil)
         (persisted-displaced-blocks nil))
    (unless database-head-number
      (block-validation-fail
       "Forkchoice delta export requires a persisted head checkpoint"))
    (loop for number from current-head-number downto 0
          for current-hash = (chain-store-canonical-hash store number)
          do (multiple-value-bind (persisted-hash present-p)
                 (kv-get-chain-canonical-hash database number)
               (when (and current-hash
                          present-p
                          (bytes= persisted-hash
                                  (hash32-bytes current-hash)))
                 (loop-finish))
               (when present-p
                 (push
                  (node-store-database-canonical-block
                   database number persisted-hash)
                  persisted-displaced-blocks))
               (when (or current-hash present-p)
                 (setf (gethash number numbers) t)
                 (when current-hash
                   (let ((block (chain-store-block-by-number store number)))
                     (unless (and block
                                  (hash32= (block-hash block) current-hash))
                       (block-validation-fail
                        "Current canonical block is missing at height ~D"
                        number))
                     (push block blocks))))))
    (when (and database-head-number
               (> database-head-number current-head-number))
      (loop for number from (1+ current-head-number)
              to database-head-number
            do (multiple-value-bind (persisted-hash present-p)
                   (kv-get-chain-canonical-hash database number)
                 (when present-p
                   (push
                    (node-store-database-canonical-block
                     database number persisted-hash)
                    persisted-displaced-blocks)
                   (setf (gethash number numbers) t)))))
    (values
     (sort (loop for number being the hash-keys of numbers collect number)
           #'<)
     (nreverse blocks)
     (nreverse persisted-displaced-blocks))))

(defun node-store-snap-pivot-difference
    (store transition database target-hash)
  "Validate and return the one-key canonical delta for a sparse snap pivot."
  (unless (hash32-p target-hash)
    (block-validation-fail
     "Snap pivot export target must be a hash32"))
  (let ((installed
          (canonical-chain-transition-installed-blocks transition)))
    (unless (= 1 (length installed))
      (block-validation-fail
       "Snap pivot transition must install exactly one checkpoint block"))
    (let* ((pivot (first installed))
           (pivot-hash (block-hash pivot))
           (pivot-number (block-header-number (block-header pivot)))
           (target (chain-store-known-block store target-hash))
           (database-head-number
             (node-store-database-head-number database)))
      (unless (and target
                   (engine-payload-store-ancestor-p
                    store pivot-hash target-hash))
        (block-validation-fail
         "Snap pivot export target does not descend from the checkpoint"))
      (unless (and (= pivot-number (chain-store-head-number store))
                   (hash32= pivot-hash
                            (chain-store-canonical-hash store pivot-number)))
        (block-validation-fail
         "Snap pivot transition is not the current sparse canonical head"))
      (unless (and database-head-number
                   (< database-head-number pivot-number))
        (block-validation-fail
         "Snap pivot export must advance the durable canonical head"))
      (multiple-value-bind (progress present-p)
          (node-store-read-snap-skeleton-progress database)
        (unless (and present-p
                     (= pivot-number
                        (node-store-snap-skeleton-progress-pivot-number
                         progress))
                     (hash32= pivot-hash
                              (node-store-snap-skeleton-progress-pivot-hash
                               progress))
                     (= (block-header-number (block-header target))
                        (node-store-snap-skeleton-progress-target-number
                         progress))
                     (hash32= target-hash
                              (node-store-snap-skeleton-progress-target-hash
                               progress))
                     (= (node-store-snap-skeleton-progress-last-number progress)
                        (node-store-snap-skeleton-progress-target-number
                         progress))
                     (hash32=
                      (node-store-snap-skeleton-progress-last-hash progress)
                      target-hash))
          (block-validation-fail
           "Snap pivot export lacks matching completed skeleton evidence")))
      (multiple-value-bind (state-root present-p)
          (kv-get-chain-record
           database :state-history (hash32-bytes pivot-hash))
        (unless (and present-p
                     (= 32 (length state-root))
                     (bytes= state-root
                             (hash32-bytes
                              (block-header-state-root
                               (block-header pivot)))))
          (block-validation-fail
           "Snap pivot export lacks its verified durable state root")))
      (values (list pivot-number) (list pivot) nil))))

(defun node-store-transition-affected-numbers (transition)
  (let ((numbers (make-hash-table :test 'eql)))
    (dolist (block (node-store-transition-blocks transition))
      (unless (typep block 'ethereum-block)
        (block-validation-fail
         "Forkchoice transition contains a non-block entry"))
      (setf (gethash (block-header-number (block-header block)) numbers) t))
    (sort (loop for number being the hash-keys of numbers collect number) #'<)))

(defun node-store-transition-affected-transaction-hashes
    (transition &optional additional-blocks)
  (let ((hashes (make-hash-table :test 'equalp)))
    (dolist (block
             (append (node-store-transition-blocks transition)
                     additional-blocks))
      (dolist (transaction (block-transactions block))
        (let ((hash (transaction-hash transaction)))
          (setf (gethash (hash32-to-hex hash) hashes) hash))))
    (dolist (hash (canonical-chain-transition-changed-txpool-hashes transition))
      (unless (hash32-p hash)
        (block-validation-fail
         "Forkchoice transition contains a non-hash txpool change"))
      (setf (gethash (hash32-to-hex hash) hashes) hash))
    (mapcar
     (lambda (key) (gethash key hashes))
     (sort (loop for key being the hash-keys of hashes collect key) #'string<))))

(defun node-store-final-overlay-transaction-location
    (chain-store transaction-hash)
  "Return TRANSACTION-HASH's post-transition in-memory canonical location.

Forkchoice mutates the memory overlay before its replacement WAL batch is
published.  A missing overlay entry for a displaced transaction is therefore
authoritative at this seam: falling through to the durable provider would read
the deliberately stale pre-transition location and reject it as non-canonical
before this exporter can delete it.  Ordinary public lookups retain their full
durable validation."
  (gethash
   (engine-payload-store-key transaction-hash)
   (memory-chain-store-transaction-locations chain-store)))

(defun node-store-final-txpool-record (store transaction-hash)
  "Return the final encoded txpool record and its transaction as two values."
  (let ((entries nil))
    (flet ((collect-entry (subpool transaction)
             (when transaction
               (push (cons subpool transaction) entries))))
      (collect-entry
       :pending
       (engine-payload-store-pending-transaction store transaction-hash))
      (collect-entry
       :queued
       (engine-payload-store-queued-transaction store transaction-hash))
      (collect-entry
       :basefee
       (engine-payload-store-basefee-transaction store transaction-hash))
      (collect-entry
       :blob
       (engine-payload-store-blob-transaction store transaction-hash)))
    (when (< 1 (length entries))
      (block-validation-fail
       "Forkchoice transition left a transaction in multiple txpool subpools"))
    (when entries
      (values
       (chain-store-txpool-transaction-record-rlp
        (caar entries) (cdar entries))
       (cdar entries)))))

(defun node-store-current-state-anchor-identifiers (store)
  (let ((identifiers (make-hash-table :test 'equal)))
    (dolist (checkpoint
              (list (chain-store-head-checkpoint store)
                    (chain-store-safe-checkpoint store)
                    (chain-store-finalized-checkpoint store)))
      (let ((hash (and checkpoint
                       (chain-store-checkpoint-block-hash checkpoint))))
        (when hash
          (setf (gethash (hash32-to-hex hash) identifiers) t))))
    identifiers))

(defun node-store-database-block-number (database identifier label)
  (multiple-value-bind (record present-p)
      (kv-get-chain-record database :block identifier)
    (unless present-p
      (block-validation-fail "~A references a missing block" label))
    (block-header-number
     (block-header
      (chain-store-block-from-persisted-record
       database identifier record label)))))

(defun node-store-call-with-ordered-state-history-range
    (database start-number end-number function)
  "Call FUNCTION with NUMBER, BLOCK-IDENTIFIER, and ROOT in [START, END)."
  (when (< start-number end-number)
    (multiple-value-bind (iterator close-iterator)
        (kv-iterator
         database
         :start
         (kv-chain-record-key
          :ordered-state-history
          (kv-chain-record-uint64-bytes start-number))
         :end
         (kv-chain-record-key
          :ordered-state-history
          (kv-chain-record-uint64-bytes end-number)))
      (unwind-protect
           (loop
             (multiple-value-bind (key root present-p)
                 (funcall iterator)
               (unless present-p
                 (return))
               (multiple-value-bind (number identifier)
                   (kv-chain-height-hash-identifier-values
                    (kv-chain-record-key-identifier
                     :ordered-state-history key))
                 (funcall function number identifier root))))
        (when close-iterator
          (funcall close-iterator))))))

(defun node-store-delete-retained-state-records
    (database batch identifier &optional number)
  "Delete one block's root and any legacy flat representation from BATCH."
  ;; These unconditional deletes deliberately follow any state puts already in
  ;; BATCH.  That matters on a deep reorg which installs a state at a height
  ;; already outside the window: consulting DATABASE alone cannot see the
  ;; pending put, while write-batch order makes the final delete authoritative.
  (dolist (kind '(:state-history :state :state-diff))
    (kv-batch-delete-chain-record batch kind identifier))
  (kv-batch-delete-chain-record
   batch
   :ordered-state-history
   (kv-chain-height-hash-identifier
    (or number
        (node-store-database-block-number
         database identifier "Retained state"))
    identifier))
  t)

(defun node-store-populate-state-retention-batch
  (store transition database batch &optional additional-blocks)
  "Prune newly expired state roots through their bounded height range.

Normal head advancement considers one newly expired canonical height.  A head
jump considers only the skipped heights, a reorg additionally considers its
displaced blocks, and an old safe/finalized anchor is reconsidered when the
checkpoint moves.  The only range scan is over the newly expired heights in the
ordered state-root index, so work follows candidate count at that boundary and
the transition rather than total retained history.  Trie nodes and code remain
content-addressed and shared; REBUILD is the offline compaction path."
  (let* ((database-head-number (node-store-database-head-number database))
         (current-head-number (chain-store-head-number store))
         (depth (memory-chain-store-state-retention-depth store))
         (database-first-kept
           (max 0 (1+ (- database-head-number depth))))
         (current-first-kept
           (max 0 (1+ (- current-head-number depth))))
         (anchors (node-store-current-state-anchor-identifiers store))
         (expired (make-hash-table :test 'equal)))
    (labels ((anchor-p (identifier)
               (gethash (bytes-to-hex identifier) anchors))
             (remember (identifier &optional number)
               (when (and identifier
                          (= 32 (length identifier))
                          (not (anchor-p identifier)))
                 (let* ((key (bytes-to-hex identifier))
                        (existing (gethash key expired)))
                   (setf (gethash key expired)
                         (cons (copy-seq identifier)
                               (or number (and existing (cdr existing))))))))
             (remember-below-boundary (identifier label)
               (when identifier
                 (let ((number
                         (node-store-database-block-number
                          database identifier label)))
                   (when (< number current-first-kept)
                     (remember identifier number)))))
             (remember-expired-blocks (blocks)
               (dolist (block blocks)
                 (let ((number
                         (block-header-number (block-header block))))
                   (when (< number current-first-kept)
                     (remember (hash32-bytes (block-hash block)) number))))))
      ;; The ordered root index visits every canonical or side-chain state at
      ;; only the heights newly crossing the boundary. This also collects
      ;; abandoned candidates that never appeared in a later transition.
      (when (> current-first-kept database-first-kept)
        (node-store-call-with-ordered-state-history-range
         database database-first-kept current-first-kept
         (lambda (number identifier root)
           (declare (ignore root))
           (remember identifier number))))
      ;; A checkpoint anchor can be much older than the window.  Once it moves,
      ;; the old root is no longer protected even if the head did not advance.
      (dolist (label '(:head :safe :finalized))
        (multiple-value-bind (identifier present-p)
            (kv-get-chain-checkpoint database label)
          (when (and present-p (not (anchor-p identifier)))
            (remember-below-boundary
             identifier "Persisted retention checkpoint"))))
      ;; A same-height deep reorg does not move the boundary, so explicitly
      ;; reconsider both sides of this transition and any reconciled blocks the
      ;; persisted/current canonical-difference walk discovered.
      (remember-expired-blocks
       (canonical-chain-transition-displaced-blocks transition))
      (remember-expired-blocks
       (canonical-chain-transition-installed-blocks transition))
      (remember-expired-blocks additional-blocks)
      (let ((changed-p nil))
        (maphash
         (lambda (key entry)
           (declare (ignore key))
           (when (node-store-delete-retained-state-records
                  database batch (car entry) (cdr entry))
             (setf changed-p t)))
         expired)
        changed-p))))

(defun node-store-export-payload-candidate-to-kv
    (store candidate database
     &key peer-sync-progress durable-forkchoice-hint-p)
  "Persist CANDIDATE and its ancestry without publishing canonical indexes.

When PEER-SYNC-PROGRESS is supplied, its cursor is committed in the same KV
batch as the candidate and must name CANDIDATE exactly.

DURABLE-FORKCHOICE-HINT-P is reserved for Engine newPayload.  After its batch
commits, a one-slot process-local hint lets the immediately following
forkchoice avoid reopening the same immutable and state records.  Peer/SNAP
imports must not set it because their pivot publication has distinct state
durability obligations."
  (let ((chain-store (chain-store-require-memory-store store)))
    (engine-payload-store-enable-durable-cache-change-tracking chain-store)
    (unless (typep candidate 'ethereum-block)
      (block-validation-fail
       "Payload candidate export requires an Ethereum block"))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Payload candidate export target must be a key-value database"))
    (let* ((candidate-hash (block-hash candidate))
           (stored-candidate
             (chain-store-known-block chain-store candidate-hash)))
      (unless stored-candidate
        (block-validation-fail
         "Payload candidate export requires a known block"))
      (unless (chain-store-persisted-block= stored-candidate candidate)
        (block-validation-fail
         "Payload candidate does not match the known block"))
      (unless (chain-store-state-available-p chain-store candidate-hash)
        (block-validation-fail
         "Payload candidate export requires available state"))
      (when peer-sync-progress
        (unless (node-store-peer-sync-progress-p peer-sync-progress)
          (block-validation-fail
           "Payload candidate peer sync progress is invalid"))
        (node-store-validate-peer-sync-progress
         database peer-sync-progress)
        (unless (and
                 (= (node-store-peer-sync-progress-last-number
                     peer-sync-progress)
                    (block-header-number (block-header stored-candidate)))
                 (hash32=
                  (node-store-peer-sync-progress-last-hash
                   peer-sync-progress)
                  candidate-hash))
          (block-validation-fail
           "Payload candidate does not match peer sync progress")))
      (let* ((batch (make-kv-write-batch))
             (code-sink (make-node-store-code-sink batch database))
             (changed-p nil)
             (pending-trie-nodes nil)
             (persisted-state-hashes nil)
             (persisted-blocks nil)
             (invalid-evicted nil)
             (remote-evicted nil)
             (current stored-candidate))
        (loop
          (let* ((hash (block-hash current))
                 (header (block-header current))
                 (number (block-header-number header))
                 (identifier (hash32-bytes hash))
                 (current-changed-p nil))
            (pushnew current persisted-blocks
                     :test (lambda (left right)
                             (hash32= (block-hash left) (block-hash right))))
            (when (node-store-put-immutable-block-records
                   database batch current "Payload candidate")
              (setf changed-p t
                    current-changed-p t))
            (when (node-store-populate-blob-sidecars-for-transactions-batch
                   chain-store database batch
                   (block-transactions current))
              (setf changed-p t
                    current-changed-p t))
            (when (chain-store-state-available-p chain-store hash)
              (push hash persisted-state-hashes)
              (multiple-value-bind (state-changed-p nodes)
                  (node-store-put-state-record
                   chain-store database batch hash identifier
                   "Payload candidate" code-sink)
                (when state-changed-p
                  (setf changed-p t
                        current-changed-p t))
                (setf pending-trie-nodes
                      (nconc pending-trie-nodes nodes))))
            ;; A direct provider's first unchanged ancestor is a durable batch
            ;; boundary. The compatibility memory/file oracle must walk its
            ;; ancestry because pruning can promote an older :DIFF to
            ;; :BASELINE without changing the candidate tip itself. Production
            ;; public presets use the bounded direct-provider branch.
            (when (or (and (chain-store-durable-state-provider-p chain-store)
                           (not current-changed-p))
                      (zerop number)
                      (hash32= (block-header-parent-hash header)
                               (zero-hash32)))
              (return))
            (let* ((parent-hash (block-header-parent-hash header))
                   (parent
                     (chain-store-known-block chain-store parent-hash)))
              (unless parent
                (block-validation-fail
                 "Payload candidate ancestry is incomplete"))
              (unless (= (block-header-number (block-header parent))
                         (1- number))
                (block-validation-fail
                 "Payload candidate ancestry has non-consecutive heights"))
              (setf current parent))))
        ;; Execution removes this block from the in-memory remote cache.  Its
        ;; durable counterpart must disappear atomically with publication of
        ;; the validated candidate, while shared BAL side data remains live
        ;; under the candidate's public :BLOCK record.
        (multiple-value-bind (remote-record remote-present-p)
            (kv-get-chain-record
             database :remote-block (hash32-bytes candidate-hash))
          (declare (ignore remote-record))
          (kv-batch-delete-chain-record
           batch :remote-block (hash32-bytes candidate-hash))
          (when remote-present-p
            (setf changed-p t)))
        ;; Reads performed during admission can expire either durable cache.
        ;; Consume every changed-key tombstone in this same candidate batch so
        ;; a crash cannot resurrect an already-evicted verdict or sync target.
        (multiple-value-bind (invalid-changed-p evicted)
            (chain-store-populate-invalid-tipset-export-batch
             chain-store database batch :write-current-p nil)
          (setf invalid-evicted evicted)
          (when invalid-changed-p
            (setf changed-p t)))
        (multiple-value-bind (remote-changed-p evicted)
            (chain-store-populate-remote-block-export-batch
             chain-store database batch :write-current-p nil)
          (setf remote-evicted evicted)
          (when (node-store-populate-evicted-remote-bal-cleanup-batch
                 chain-store database batch
                 (append invalid-evicted remote-evicted)
                 :deleted-remote-identifiers remote-evicted
                 :deleted-invalid-identifiers invalid-evicted)
            (setf changed-p t))
          (when remote-changed-p
            (setf changed-p t)))
        (when (and peer-sync-progress
                   (node-store-populate-peer-sync-progress-batch
                    database batch peer-sync-progress))
          (setf changed-p t))
        (when changed-p
          (kv-apply-batch database batch)
          (mpt-mark-nodes-persisted pending-trie-nodes)
          (dolist (hash persisted-state-hashes)
            (chain-store-clear-state-persistence-pending chain-store hash)))
        (node-store-clear-durable-cache-deletions
         (memory-chain-store-invalid-tipset-durable-deletions chain-store)
         invalid-evicted)
        (node-store-clear-durable-cache-deletions
         (memory-chain-store-remote-block-durable-deletions chain-store)
         (append remote-evicted (list (hash32-bytes candidate-hash))))
        (dolist (block persisted-blocks)
          (chain-store-release-durable-block-overlay chain-store block))
        (when (and durable-forkchoice-hint-p
                   (chain-store-durable-state-provider-p chain-store))
          (setf (memory-chain-store-durable-engine-payload-hash chain-store)
                (make-hash32 (hash32-bytes candidate-hash))))
        database))))

(defun node-store-export-invalid-candidate-to-kv
    (store candidate database)
  "Persist an INVALID verdict and remove stale buffered records atomically."
  (let ((chain-store (chain-store-require-memory-store store)))
    (engine-payload-store-enable-durable-cache-change-tracking chain-store)
    (unless (typep candidate 'ethereum-block)
      (block-validation-fail
       "Invalid candidate export requires an Ethereum block"))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Invalid candidate export target must be a key-value database"))
    ;; The import transaction already admitted/pruned this verdict with its
    ;; chosen cache clock.  A durability sink must not call the public getter,
    ;; whose default NOW would advance a deterministic/test clock and could
    ;; evict the very verdict being committed.  Read the transaction-local
    ;; table directly; values are immutable copied blocks.
    (let ((invalid-block
            (gethash
             (engine-payload-store-key (block-hash candidate))
             (memory-chain-store-invalid-tipsets chain-store))))
      (unless invalid-block
        (block-validation-fail
         "Invalid candidate export requires an invalid cache verdict"))
      (when (chain-store-known-block chain-store (block-hash candidate))
        (block-validation-fail
         "Invalid candidate export refuses a known executed block"))
      (when (chain-store-known-block chain-store (block-hash invalid-block))
        (block-validation-fail
         "Invalid candidate export refuses a known invalid ancestor"))
      (let ((batch (make-kv-write-batch))
            (changed-p nil)
            (invalid-evicted nil)
            (remote-evicted nil))
      ;; A descendant verdict maps to its invalid ancestor in memory. Persist
      ;; only the retained direct owner, never a descendant key paired with a
      ;; different block body.
      (let* ((invalid-key
               (engine-payload-store-key (block-hash invalid-block)))
             (direct-owner
               (gethash invalid-key
                        (memory-chain-store-invalid-tipsets chain-store))))
        (when (and direct-owner
                   (chain-store-invalid-tipset-exportable-p
                    chain-store invalid-key direct-owner)
                   (chain-store-export-invalid-tipset-to-kv
                    database batch invalid-key direct-owner))
          (setf changed-p t)))
      (multiple-value-bind (invalid-changed-p evicted)
          (chain-store-populate-invalid-tipset-export-batch
           chain-store database batch :write-current-p nil)
        (setf invalid-evicted evicted)
        (when invalid-changed-p
          (setf changed-p t)))
      (multiple-value-bind (remote-changed-p evicted)
          (chain-store-populate-remote-block-export-batch
           chain-store database batch :write-current-p nil)
        (setf remote-evicted evicted)
        (when (node-store-populate-evicted-remote-bal-cleanup-batch
               chain-store database batch (append invalid-evicted evicted)
               :deleted-remote-identifiers evicted
               :deleted-invalid-identifiers invalid-evicted)
          (setf changed-p t))
        (when remote-changed-p
          (setf changed-p t)))
      (when changed-p
        (kv-apply-batch database batch))
      (node-store-clear-durable-cache-deletions
       (memory-chain-store-invalid-tipset-durable-deletions chain-store)
       invalid-evicted)
      (node-store-clear-durable-cache-deletions
       (memory-chain-store-remote-block-durable-deletions chain-store)
       remote-evicted)
        database))))

(defun node-store-export-buffered-candidate-to-kv
    (store candidate database)
  "Persist one unexecuted remote CANDIDATE and its BAL side data atomically.

The candidate must still be present in STORE's remote cache and must not have
become a known or invalid block.  This is the durable sink for SYNCING and
ACCEPTED payloads; it publishes no executable or canonical chain records."
  (let ((chain-store (chain-store-require-memory-store store)))
    (engine-payload-store-enable-durable-cache-change-tracking chain-store)
    (unless (typep candidate 'ethereum-block)
      (block-validation-fail
       "Buffered candidate export requires an Ethereum block"))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Buffered candidate export target must be a key-value database"))
    (let* ((candidate-hash (block-hash candidate))
           (candidate-key (engine-payload-store-key candidate-hash)))
      (multiple-value-bind (buffered present-p)
          (gethash candidate-key (memory-chain-store-remote-blocks chain-store))
        (unless present-p
          (block-validation-fail
           "Buffered candidate export requires a remote cached block"))
        (unless (chain-store-persisted-block=
                 buffered candidate :allow-missing-committed-p t)
          (block-validation-fail
           "Buffered candidate does not match its remote cached block"))
        (when (chain-store-known-block chain-store candidate-hash)
          (block-validation-fail
           "Buffered candidate export refuses a known block"))
        (when (gethash candidate-key
                       (memory-chain-store-invalid-tipsets chain-store))
          (block-validation-fail
           "Buffered candidate export refuses an invalid block"))
        (let ((batch (make-kv-write-batch))
              (changed-p nil)
              (invalid-evicted nil)
              (remote-evicted nil))
          ;; Write only this admission plus bounded eviction tombstones.  The
          ;; hot path never scans or rewrites the complete durable cache.
          (when (chain-store-export-remote-block-to-kv
                 database batch candidate-key buffered)
            (setf changed-p t))
          (multiple-value-bind (invalid-changed-p evicted)
              (chain-store-populate-invalid-tipset-export-batch
               chain-store database batch :write-current-p nil)
            (setf invalid-evicted evicted)
            (when invalid-changed-p
              (setf changed-p t)))
          (multiple-value-bind (remote-changed-p evicted)
              (chain-store-populate-remote-block-export-batch
               chain-store database batch :write-current-p nil)
            (setf remote-evicted evicted)
            (when (node-store-populate-evicted-remote-bal-cleanup-batch
                   chain-store database batch
                   (append invalid-evicted remote-evicted)
                   :deleted-remote-identifiers remote-evicted
                   :deleted-invalid-identifiers invalid-evicted)
              (setf changed-p t))
            (when remote-changed-p
              (setf changed-p t)))
          ;; A supplied and verified blob sidecar lives in the same admission
          ;; unit as this missing-parent block. Persist every available sidecar
          ;; referenced by its transactions in this WAL batch; blocks learned
          ;; without blob bodies remain legitimate buffered targets.
          (when (node-store-populate-blob-sidecars-for-transactions-batch
                 chain-store database batch (block-transactions candidate))
            (setf changed-p t))
          (when changed-p
            (kv-apply-batch database batch))
          (node-store-clear-durable-cache-deletions
           (memory-chain-store-invalid-tipset-durable-deletions chain-store)
           invalid-evicted)
          (node-store-clear-durable-cache-deletions
           (memory-chain-store-remote-block-durable-deletions chain-store)
           remote-evicted)
          database)))))

(defun node-store-export-forkchoice-to-kv
    (store transition database
     &key persistence-metadata
          (sync-pivot-target-hash nil sync-pivot-target-supplied-p))
  (let ((chain-store (chain-store-require-memory-store store)))
    (engine-payload-store-enable-durable-cache-change-tracking chain-store)
    (unless (canonical-chain-transition-p transition)
      (block-validation-fail
       "Forkchoice export requires a canonical chain transition"))
    (unless (typep database 'key-value-database)
      (block-validation-fail
       "Forkchoice export target must be a key-value database"))
    (node-store-require-persistence-metadata-for-versioned-target
     database persistence-metadata "Forkchoice")
    (unless (engine-payload-store-txpool-database-change-tracking-enabled-p
             store)
      (block-validation-fail
       "Forkchoice export requires txpool database change tracking"))
    ;; This path is direct-key by contract and must not scan the database, so
    ;; it does not migrate. It writes records in the current layout beside
    ;; records it does not touch; an older on-disk layout therefore surfaces as
    ;; NODE-STORE-PUT-IMMUTABLE-RECORD refusing the conflict. Bringing the
    ;; database forward is NODE-STORE-IMPORT-FROM-KV's job, which every node
    ;; runs before it ever exports.
    (multiple-value-bind
        (reconciled-numbers reconciled-blocks persisted-displaced-blocks)
        (if sync-pivot-target-supplied-p
            (node-store-snap-pivot-difference
             chain-store transition database sync-pivot-target-hash)
            (node-store-canonical-difference chain-store database))
      (let* ((batch (make-kv-write-batch))
             (code-sink (make-node-store-code-sink batch database))
             (changed-p nil)
             (pending-trie-nodes nil)
             (persisted-state-hashes nil)
             (installed-blocks
               (node-store-unique-blocks
                (append
                 (canonical-chain-transition-installed-blocks transition)
                 reconciled-blocks)))
             (affected-numbers (make-hash-table :test 'eql))
             (transaction-hashes
               (node-store-transition-affected-transaction-hashes
                transition
                (append reconciled-blocks persisted-displaced-blocks))))
        (dolist (number (node-store-transition-affected-numbers transition))
          (setf (gethash number affected-numbers) t))
        (dolist (number reconciled-numbers)
          (setf (gethash number affected-numbers) t))
        (dolist (number
                 (sort
                  (loop for key being the hash-keys of affected-numbers
                        collect key)
                  #'<))
          (when (node-store-sync-canonical-hash
                 database batch chain-store number)
            (setf changed-p t)))
        (dolist (entry
                 (list
                  (cons :head (chain-store-head-checkpoint chain-store))
                  (cons :safe (chain-store-safe-checkpoint chain-store))
                  (cons :finalized
                        (chain-store-finalized-checkpoint chain-store))))
          (when (node-store-sync-checkpoint
                 database batch (cdr entry) (car entry))
            (setf changed-p t)))
        (dolist (block installed-blocks)
          (let* ((hash (block-hash block))
                 (known-block (chain-store-known-block chain-store hash))
                 (identifier (hash32-bytes hash))
                 (block-records-durable-p
                   (node-store-installed-block-records-durable-p
                    chain-store block)))
            (unless (and known-block
                         (chain-store-persisted-block= known-block block)
                         (chain-store-canonical-block-p chain-store block))
              (block-validation-fail
               "Forkchoice transition installed block is not canonical"))
            (unless block-records-durable-p
              (when (node-store-put-immutable-block-records
                     database batch block "Forkchoice transition")
                (setf changed-p t)))
            (when (node-store-populate-blob-sidecars-for-transactions-batch
                   chain-store database batch (block-transactions block))
              (setf changed-p t))
            (when (and
                   (chain-store-state-available-p chain-store hash)
                   (not
                    (node-store-installed-state-record-durable-p
                     chain-store block)))
              (push hash persisted-state-hashes)
              (multiple-value-bind (state-changed-p nodes)
                  (node-store-put-state-record
                   chain-store database batch hash identifier
                   "Forkchoice transition" code-sink)
                (when state-changed-p
                  (setf changed-p t))
                (setf pending-trie-nodes
                      (nconc pending-trie-nodes nodes))))))
        (dolist (transaction-hash transaction-hashes)
          (let* ((identifier (hash32-bytes transaction-hash))
                 (location
                   (node-store-final-overlay-transaction-location
                    chain-store transaction-hash))
                 (location-value
                   (and location
                        (chain-store-canonical-block-p
                         chain-store
                         (engine-transaction-location-block location))
                        (transaction-location-record-rlp location))))
            (when (node-store-sync-chain-record
                   database batch :transaction-location identifier
                   location-value)
              (setf changed-p t))
            (multiple-value-bind (txpool-record txpool-transaction)
                (node-store-final-txpool-record store transaction-hash)
              (when (node-store-sync-chain-record
                     database batch :txpool identifier txpool-record)
                (setf changed-p t))
              (when (and txpool-transaction
                         (node-store-populate-blob-sidecars-for-transactions-batch
                          chain-store database batch
                          (list txpool-transaction)
                          :require-all-p t))
                (setf changed-p t)))))
        (when (and (not sync-pivot-target-supplied-p)
                   (chain-store-durable-state-provider-p chain-store)
                   (node-store-populate-state-retention-batch
                    chain-store transition database batch installed-blocks))
          (setf changed-p t))
        ;; Finality/age/count pruning ran before this exporter. Synchronize the
        ;; bounded invalid and remote sets in the same forkchoice WAL batch so a
        ;; quiet node cannot retain pruned verdicts/targets forever on disk.
        (let ((invalid-evicted nil)
              (remote-evicted nil))
          (multiple-value-bind (invalid-changed-p evicted)
            (chain-store-populate-invalid-tipset-export-batch
             chain-store database batch :write-current-p nil)
            (setf invalid-evicted evicted)
          (when invalid-changed-p
            (setf changed-p t))
          (multiple-value-bind (remote-changed-p evicted)
            (chain-store-populate-remote-block-export-batch
             chain-store database batch :write-current-p nil)
            (setf remote-evicted evicted)
            (when (node-store-populate-evicted-remote-bal-cleanup-batch
                   chain-store database batch
                   (append invalid-evicted remote-evicted)
                   :deleted-remote-identifiers remote-evicted
                   :deleted-invalid-identifiers invalid-evicted)
              (setf changed-p t))
            (when remote-changed-p
              (setf changed-p t))))
        (when changed-p
          ;; Metadata describes a durable mutation, not receipt of an
          ;; idempotent forkchoice request.  In particular, a consensus client
          ;; asks for a child build by repeating the current head; writing only
          ;; a new generation for that no-op would force one RocksDB WAL sync
          ;; per block without publishing any new chain fact.
          (when persistence-metadata
            (node-store-populate-persistence-metadata-batch
             batch persistence-metadata))
          (kv-apply-batch database batch)
          (mpt-mark-nodes-persisted pending-trie-nodes)
          (dolist (hash persisted-state-hashes)
            (chain-store-clear-state-persistence-pending chain-store hash)))
        (node-store-clear-durable-cache-deletions
         (memory-chain-store-invalid-tipset-durable-deletions chain-store)
         invalid-evicted)
        (node-store-clear-durable-cache-deletions
         (memory-chain-store-remote-block-durable-deletions chain-store)
         remote-evicted))
        (dolist (block installed-blocks)
          (chain-store-release-durable-block-overlay chain-store block))
        (let ((hint
                (memory-chain-store-durable-engine-payload-hash chain-store)))
          (when (and hint
                     (find hint installed-blocks
                           :key #'block-hash :test #'hash32=))
            (setf
             (memory-chain-store-durable-engine-payload-hash chain-store)
             nil)))
        (engine-payload-store-clear-txpool-database-dirty-transaction-hashes
         store transaction-hashes)
        (values database changed-p)))))

(defun node-store-block-access-list-live-identifiers (store database)
  "Return the block identifiers that may reference shared BAL side data.

The full export batch makes the in-memory known, remote, and invalid block
tables authoritative.  Persisted block records are append-only, while staged
block records have an independent lifecycle, so their existing identifiers
also remain live."
  (let ((live-identifiers (make-hash-table :test 'equalp)))
    (labels ((mark-identifier (identifier)
               (setf (gethash (bytes-to-hex identifier) live-identifiers) t))
             (mark-memory-blocks (blocks)
               (maphash
                (lambda (key block)
                  (declare (ignore key))
                  (mark-identifier (hash32-bytes (block-hash block))))
                blocks))
             (mark-persisted-records (kind)
               (dolist (entry (kv-chain-record-entries database kind))
                 (mark-identifier (car entry)))))
      (mark-memory-blocks (memory-chain-store-blocks store))
      (mark-memory-blocks (memory-chain-store-remote-blocks store))
      (mark-memory-blocks (memory-chain-store-invalid-tipsets store))
      (mark-persisted-records :block)
      (mark-persisted-records :staged-block))
    live-identifiers))

(defun node-store-populate-block-access-list-sweep-batch
    (store database batch)
  "Delete BAL side records unreferenced by the full export's final bodies."
  (let ((live-identifiers
          (node-store-block-access-list-live-identifiers store database)))
    (dolist (entry (kv-chain-record-entries database :block-access-list))
      (unless (gethash (bytes-to-hex (car entry)) live-identifiers)
        (kv-batch-delete-chain-record
         batch :block-access-list (car entry)))))
  batch)

(defun node-store-export-to-kv
    (store database &key persistence-metadata)
  (let ((chain-store (chain-store-require-memory-store store)))
    (engine-payload-store-enable-durable-cache-change-tracking chain-store)
    (when (chain-store-durable-state-provider-p chain-store)
      (block-validation-fail
       "Full node export requires an authoritative memory/file oracle; direct database stores use changed-key persistence"))
    (unless (typep database 'key-value-database)
      (block-validation-fail "Node export target must be a key-value database"))
    (node-store-require-persistence-metadata-for-versioned-target
     database persistence-metadata "Node")
    ;; The full export rewrites :STATE and :STATE-DIFF itself but leaves the
    ;; staged area alone, so an unmigrated staged record would survive beside
    ;; the new layout under the new marker.
    (node-store-migrate-chain-schema database)
    (let ((batch (make-kv-write-batch))
          (pending-trie-nodes nil)
          (persisted-state-hashes nil)
          (invalid-evicted nil)
          (remote-evicted nil))
      (chain-store-populate-index-export-batch chain-store database batch)
      (chain-store-populate-block-record-export-batch
       chain-store database batch)
      (chain-store-populate-transaction-location-export-batch
       chain-store database batch)
      (multiple-value-bind (ignored nodes state-hashes)
          (chain-store-populate-state-record-export-batch
           chain-store database batch)
        (declare (ignore ignored))
        (setf pending-trie-nodes nodes
              persisted-state-hashes state-hashes))
      (chain-store-populate-txpool-record-export-batch store database batch)
      (multiple-value-bind (ignored deleted)
          (chain-store-populate-invalid-tipset-export-batch
           chain-store database batch :authoritative-p t)
        (declare (ignore ignored))
        (setf invalid-evicted deleted))
      (multiple-value-bind (ignored deleted)
          (chain-store-populate-remote-block-export-batch
           chain-store database batch :authoritative-p t)
        (declare (ignore ignored))
        (setf remote-evicted deleted))
      (chain-store-populate-blob-sidecar-export-batch
       chain-store database batch)
      (chain-store-populate-prepared-payload-export-batch
       chain-store database batch)
      (node-store-populate-block-access-list-sweep-batch
       chain-store database batch)
      (node-store-populate-persistence-metadata-batch
       batch persistence-metadata)
      (kv-apply-batch database batch)
      (node-store-clear-durable-cache-deletions
       (memory-chain-store-invalid-tipset-durable-deletions chain-store)
       invalid-evicted)
      (node-store-clear-durable-cache-deletions
       (memory-chain-store-remote-block-durable-deletions chain-store)
       remote-evicted)
      (mpt-mark-nodes-persisted pending-trie-nodes)
      (dolist (hash persisted-state-hashes)
        (chain-store-clear-state-persistence-pending chain-store hash))
      database)))
