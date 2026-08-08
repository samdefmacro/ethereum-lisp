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
    (database batch block record-label)
  (let ((identifier (hash32-bytes (block-hash block)))
        (changed-p nil))
    (when (node-store-put-immutable-block-body-record
           database batch :block block record-label)
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
    (store candidate database)
  "Persist CANDIDATE and its ancestry without publishing canonical indexes."
  (let ((chain-store (chain-store-require-memory-store store)))
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
      (let* ((batch (make-kv-write-batch))
             (code-sink (make-node-store-code-sink batch database))
             (changed-p nil)
             (pending-trie-nodes nil)
             (persisted-state-hashes nil)
             (persisted-blocks nil)
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
        (when changed-p
          (kv-apply-batch database batch)
          (mpt-mark-nodes-persisted pending-trie-nodes)
          (dolist (hash persisted-state-hashes)
            (chain-store-clear-state-persistence-pending chain-store hash)))
        (dolist (block persisted-blocks)
          (chain-store-release-durable-block-overlay chain-store block))
        database))))

(defun node-store-export-forkchoice-to-kv
    (store transition database &key persistence-metadata)
  (let ((chain-store (chain-store-require-memory-store store)))
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
        (node-store-canonical-difference chain-store database)
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
                 (identifier (hash32-bytes hash)))
            (unless (and known-block
                         (chain-store-persisted-block= known-block block)
                         (chain-store-canonical-block-p chain-store block))
              (block-validation-fail
               "Forkchoice transition installed block is not canonical"))
            (when (node-store-put-immutable-block-records
                   database batch block "Forkchoice transition")
              (setf changed-p t))
            (when (node-store-populate-blob-sidecars-for-transactions-batch
                   chain-store database batch (block-transactions block))
              (setf changed-p t))
            (when (chain-store-state-available-p chain-store hash)
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
                   (chain-store-transaction-location
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
        (when (and (chain-store-durable-state-provider-p chain-store)
                   (node-store-populate-state-retention-batch
                    chain-store transition database batch installed-blocks))
          (setf changed-p t))
        (when persistence-metadata
          (node-store-populate-persistence-metadata-batch
           batch persistence-metadata)
          (setf changed-p t))
        (when changed-p
          (kv-apply-batch database batch)
          (mpt-mark-nodes-persisted pending-trie-nodes)
          (dolist (hash persisted-state-hashes)
            (chain-store-clear-state-persistence-pending chain-store hash)))
        (dolist (block installed-blocks)
          (chain-store-release-durable-block-overlay chain-store block))
        (engine-payload-store-clear-txpool-database-dirty-transaction-hashes
         store transaction-hashes)
        database))))

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
          (persisted-state-hashes nil))
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
      (chain-store-populate-invalid-tipset-export-batch
       chain-store database batch)
      (chain-store-populate-remote-block-export-batch
       chain-store database batch)
      (chain-store-populate-blob-sidecar-export-batch
       chain-store database batch)
      (chain-store-populate-prepared-payload-export-batch
       chain-store database batch)
      (node-store-populate-block-access-list-sweep-batch
       chain-store database batch)
      (node-store-populate-persistence-metadata-batch
       batch persistence-metadata)
      (kv-apply-batch database batch)
      (mpt-mark-nodes-persisted pending-trie-nodes)
      (dolist (hash persisted-state-hashes)
        (chain-store-clear-state-persistence-pending chain-store hash))
      database)))
