(in-package #:ethereum-lisp.node-store.persistence)

(defun state-storage-entry-rlp-object (entry)
  (make-rlp-list
   (hash32-bytes (car entry))
   (cdr entry)))

(defun state-account-snapshot-rlp-object
    (address balance nonce code storage-entries code-sink)
  (make-rlp-list
   (address-bytes address)
   balance
   nonce
   (node-store-code-sink-put code-sink code)
   (apply #'make-rlp-list
          (mapcar #'state-storage-entry-rlp-object storage-entries))))

(defun chain-store-state-record-rlp (store block-hash &key code-sink)
  "Encode BLOCK-HASH's full account snapshot.

With CODE-SINK each account carries the content address of its code and the
body goes to the sink (schema v3+); without one the body is inlined, which is
the pre-v3 layout the migration reads."
  (let ((accounts '()))
    (chain-store-for-each-account
     store
     block-hash
     (lambda (address balance nonce code storage-entries)
       (push
        (state-account-snapshot-rlp-object
         address balance nonce code storage-entries code-sink)
        accounts)))
    (rlp-encode (apply #'make-rlp-list (nreverse accounts)))))

(defun chain-store-export-state-record-to-kv
    (store batch block-key code-sink)
  (let ((block-hash (hash32-from-hex block-key)))
    (kv-batch-put-chain-record
     batch
     :state
     (hash32-bytes block-hash)
     (chain-store-state-record-rlp store block-hash :code-sink code-sink))))

(defun chain-store-state-record-kind (store block-key)
  "Return :BASELINE, :DIFF, :TRIE, or NIL for BLOCK-KEY."
  (let ((kind (gethash block-key
                       (memory-chain-store-state-blocks store))))
    (if (and (null kind)
             (chain-store-durable-state-provider-p store)
             (chain-store-state-root store (hash32-from-hex block-key)))
        :trie
        (case kind
          ((:baseline :diff :trie nil) kind)
          (t :baseline)))))

(defun state-diff-field-rlp (value empty)
  "Encode one diff field as (VALUES TAG VALUE): 0 carries no change, 1 a new
value, 2 an account tombstone."
  (cond
    ((null value) (values 0 empty))
    ((eq value :absent) (values 2 empty))
    (t (values 1 value))))

(defun state-diff-account-rlp-object (address-hex diff code-sink)
  (let ((address (address-from-hex address-hex))
        (account-prefix (format nil "~A:" address-hex))
        (storage-entries '()))
    (maphash
     (lambda (suffix value)
       (when (and (<= (length account-prefix) (length suffix))
                  (string= account-prefix suffix
                           :end2 (length account-prefix)))
         (push (cons (subseq suffix (length account-prefix)) value)
               storage-entries)))
     (chain-state-diff-storage diff))
    (multiple-value-bind (balance-tag balance)
        (state-diff-field-rlp
         (gethash address-hex (chain-state-diff-balances diff)) 0)
      (multiple-value-bind (nonce-tag nonce)
          (state-diff-field-rlp
           (gethash address-hex (chain-state-diff-nonces diff)) 0)
        (multiple-value-bind (code-tag code)
            (state-diff-field-rlp
             (gethash address-hex (chain-state-diff-codes diff))
             (make-byte-vector 0))
          (make-rlp-list
           (address-bytes address)
           balance-tag balance
           nonce-tag nonce
           ;; The tag-0 and tag-2 placeholders are already empty, and an empty
           ;; body has an empty reference, so one call covers every tag.
           code-tag (node-store-code-sink-put code-sink code)
           (apply #'make-rlp-list
                  (mapcar
                   (lambda (entry)
                     (make-rlp-list
                      (hash32-bytes (hash32-from-hex (car entry)))
                      (cdr entry)))
                   (sort storage-entries #'string< :key #'car)))))))))

(defun state-diff-addresses (diff)
  (let ((addresses (make-hash-table :test 'equal)))
    (flet ((remember (table)
             (maphash (lambda (suffix value)
                        (declare (ignore value))
                        (setf (gethash suffix addresses) t))
                      table)))
      (remember (chain-state-diff-balances diff))
      (remember (chain-state-diff-nonces diff))
      (remember (chain-state-diff-codes diff)))
    (maphash (lambda (suffix value)
               (declare (ignore value))
               (let ((separator (position #\: suffix)))
                 (when separator
                   (setf (gethash (subseq suffix 0 separator) addresses)
                         t))))
             (chain-state-diff-storage diff))
    (sort (loop for address being the hash-keys of addresses
                collect address)
          #'string<)))

(defun chain-store-state-diff-record-rlp (store block-key &key code-sink)
  (let ((diff (gethash block-key
                       (memory-chain-store-state-diffs store))))
    (unless diff
      (block-validation-fail
       "State diff block ~A has no diff to export" block-key))
    (rlp-encode
     (make-rlp-list
      (hash32-bytes (hash32-from-hex (chain-state-diff-parent-key diff)))
      (apply #'make-rlp-list
             (mapcar
              (lambda (address-hex)
                (state-diff-account-rlp-object address-hex diff code-sink))
              (state-diff-addresses diff)))))))

(defun chain-store-export-state-diff-record-to-kv
    (store batch block-key code-sink)
  (kv-batch-put-chain-record
   batch
   :state-diff
   (hash32-bytes (hash32-from-hex block-key))
   (chain-store-state-diff-record-rlp store block-key :code-sink code-sink)))

(defun chain-store-populate-state-trie-record-to-kv
    (store database batch block-hash identifier record-label code-sink)
  "Add BLOCK-HASH's root and dirty trie paths to BATCH.

Returns (VALUES CHANGED-P NODES).  NODES must be marked persisted only after
the encompassing batch succeeds.  A store imported from the legacy flat
layout has no root/tries yet and returns NIL, allowing the resumable schema
migration to establish them separately."
  (let ((root (chain-store-state-root store block-hash))
        (tries (chain-store-state-persistence-tries store block-hash))
        (nodes nil)
        (changed-p nil))
    (when root
      (let ((block (chain-store-known-block store block-hash)))
        (unless block
          (block-validation-fail "~A references an unknown block" record-label))
        (unless (hash32= root (block-header-state-root (block-header block)))
          (block-validation-fail
           "~A state root does not match its block header" record-label))
        (let* ((root-bytes (hash32-bytes root))
               (ordered-identifier
                 (kv-chain-height-hash-identifier
                  (block-header-number (block-header block)) identifier)))
          (multiple-value-bind (existing present-p)
              (kv-get-chain-record database :state-history identifier)
            (cond
              ((not present-p)
               (unless tries
                 (block-validation-fail
                  "~A has an unpersisted state root but no dirty trie set"
                  record-label))
               (kv-batch-put-chain-record
                batch :state-history identifier root-bytes)
               (setf changed-p t))
              ((not (bytes= existing root-bytes))
               (block-validation-fail
                "~A conflicts with persisted state history" record-label))))
          (multiple-value-bind (ordered-root ordered-p)
              (kv-get-chain-record
               database :ordered-state-history ordered-identifier)
            (cond
              ((not ordered-p)
               (kv-batch-put-chain-record
                batch :ordered-state-history ordered-identifier root-bytes)
               (setf changed-p t))
              ((not (bytes= ordered-root root-bytes))
               (block-validation-fail
                "~A conflicts with height-ordered state history"
                record-label))))))
      (dolist (trie tries)
        (let ((dirty
                (mpt-populate-dirty-batch batch trie database)))
          (when dirty
            (setf changed-p t
                  nodes (nconc nodes dirty)))))
      (dolist (code
               (chain-store-state-persistence-code-bodies store block-hash))
        (node-store-code-sink-put code-sink code)))
    (values changed-p nodes)))

(defun chain-store-populate-state-record-export-batch
    (store database batch)
  (setf store (chain-store-require-memory-store store))
  ;; One sink for the whole batch: a contract shared by several accounts, or
  ;; carried by every block snapshot that retains it, is written once.
  (let ((code-sink (make-node-store-code-sink batch database))
        (pending-nodes nil)
        (state-hashes nil))
    (dolist (entry (kv-chain-record-entries database :state))
      (unless (eq :baseline
                  (chain-store-state-record-kind
                   store (bytes-to-hex (car entry))))
        (kv-batch-delete-chain-record batch :state (car entry))))
    (dolist (entry (kv-chain-record-entries database :state-diff))
      (unless (eq :diff
                  (chain-store-state-record-kind
                   store (bytes-to-hex (car entry))))
        (kv-batch-delete-chain-record batch :state-diff (car entry))))
    (maphash
     (lambda (block-key state-available-p)
       (when state-available-p
         (let ((block-hash (hash32-from-hex block-key)))
           (push block-hash state-hashes)
           (multiple-value-bind (changed-p nodes)
               (chain-store-populate-state-trie-record-to-kv
                store database batch block-hash
                (hash32-bytes block-hash) "State export" code-sink)
             (declare (ignore changed-p))
             (setf pending-nodes (nconc pending-nodes nodes)))
           (ecase (chain-store-state-record-kind store block-key)
             (:baseline
              (chain-store-export-state-record-to-kv
               store batch block-key code-sink))
             (:diff
              (chain-store-export-state-diff-record-to-kv
               store batch block-key code-sink))
             (:trie
              (kv-batch-delete-chain-record
               batch :state (hash32-bytes block-hash))
              (kv-batch-delete-chain-record
               batch :state-diff (hash32-bytes block-hash)))))))
     (memory-chain-store-state-blocks store))
    ;; A full memory/file-oracle export is authoritative. Remove root/index
    ;; pairs for states the oracle no longer retains; shared trie/code content
    ;; remains append-only until an offline rebuild compacts it.
    (dolist (entry
             (kv-chain-record-entries database :ordered-state-history))
      (multiple-value-bind (number identifier)
          (kv-chain-height-hash-identifier-values (car entry))
        (declare (ignore number))
        (unless (gethash (bytes-to-hex identifier)
                         (memory-chain-store-state-blocks store))
          (kv-batch-delete-chain-record
           batch :ordered-state-history (car entry))
          (kv-batch-delete-chain-record batch :state-history identifier))))
    ;; These records are the layout the marker names, so the marker travels in
    ;; the same batch: a reader can never see content-addressed accounts under
    ;; a version that says their code is inline.
    (kv-batch-put-chain-schema-version batch)
    (values batch pending-nodes state-hashes)))

(defun chain-store-export-state-records-to-kv (store database)
  (chain-store-apply-export-batch
   store database "state record"
   #'chain-store-populate-state-record-export-batch))
