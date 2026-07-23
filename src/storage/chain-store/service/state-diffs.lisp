(in-package #:ethereum-lisp.chain-store)

;;;; Per-block state diffs.
;;;;
;;;; A block's state is stored either as a BASELINE — a full account snapshot
;;;; in the block-prefixed flat tables, the historical representation — or as
;;;; a DIFF against its parent block's state (a CHAIN-STATE-DIFF). Reads
;;;; resolve through the hash-addressed diff chain to the nearest baseline,
;;;; so side chains and reorgs need no undo machinery: each branch's diffs
;;;; simply hang off their own parents. A stored default value (zero
;;;; balance/nonce, empty code, zero storage slot) shadows the parent, and
;;;; the :ABSENT marker tombstones a destroyed account outright.

(defun engine-payload-store-state-kind-for-key (store block-key)
  "Return :BASELINE, :DIFF, or NIL for BLOCK-KEY's state. Legacy stores
marked availability with T, which denotes a baseline."
  (let ((kind (gethash block-key (memory-chain-store-state-blocks store))))
    (case kind
      ((:baseline :diff nil) kind)
      (t :baseline))))

(defun chain-store-state-kind (store block-hash)
  (let ((store (chain-store-require-memory-store store)))
    (engine-payload-store-state-kind-for-key
     store (engine-payload-store-key block-hash))))

(defun engine-payload-store-state-diff-for-key (store block-key)
  (gethash block-key (memory-chain-store-state-diffs store)))

(defun engine-payload-store-state-walk-limit (store)
  "Upper bound on any diff-chain walk: an acyclic chain cannot hold more
links than there are state blocks. Imported records could otherwise form a
cycle and hang every read."
  (1+ (hash-table-count (memory-chain-store-state-blocks store))))

(defun engine-payload-store-resolve-state-value
    (store block-hash diff-table-reader suffix prefixed-table default)
  "Resolve one state value at BLOCK-HASH by walking the diff chain to a
baseline. SUFFIX is the block-independent key part (address hex, or
address:slot hex); PREFIXED-TABLE holds the baseline entries under
block-prefixed keys."
  (let* ((store (chain-store-require-memory-store store))
         (block-key (engine-payload-store-key block-hash))
         (remaining (engine-payload-store-state-walk-limit store)))
    (loop
      ;; An acyclic chain cannot be longer than the number of state
      ;; blocks; a longer walk means imported diffs form a cycle.
      (when (minusp (decf remaining))
        (return default))
      (case (engine-payload-store-state-kind-for-key store block-key)
        (:baseline
         (return (gethash (format nil "~A:~A" block-key suffix)
                          prefixed-table
                          default)))
        (:diff
         (let ((diff (engine-payload-store-state-diff-for-key
                      store block-key)))
           (unless diff
             (return default))
           (multiple-value-bind (value present-p)
               (gethash suffix (funcall diff-table-reader diff))
             (when present-p
               (return (if (eq value :absent) default value)))
             (setf block-key (chain-state-diff-parent-key diff)))))
        (t
         (return default))))))

(defun engine-payload-store-state-baseline-distance (store block-hash)
  "Number of diff links from BLOCK-HASH's state to its baseline, or NIL
when the chain does not reach one."
  (let* ((store (chain-store-require-memory-store store))
         (block-key (engine-payload-store-key block-hash))
         (remaining (engine-payload-store-state-walk-limit store))
         (distance 0))
    (loop
      (when (minusp (decf remaining))
        (return nil))
      (case (engine-payload-store-state-kind-for-key store block-key)
        (:baseline (return distance))
        (:diff
         (let ((diff (engine-payload-store-state-diff-for-key
                      store block-key)))
           (unless diff
             (return nil))
           (incf distance)
           (setf block-key (chain-state-diff-parent-key diff))))
        (t (return nil))))))

(defun chain-store-put-state-diff
    (store block-hash parent-hash &key balances nonces codes storage)
  "Install BLOCK-HASH's state as a diff against PARENT-HASH. The tables are
keyed by address hex (address:slot hex for STORAGE) and may carry :ABSENT
tombstones; zero storage values tombstone their slots."
  (let ((store (chain-store-require-memory-store store)))
    (unless (engine-payload-store-known-block store block-hash)
      (block-validation-fail
       "State diff block must be known by the memory store"))
    (unless (hash32-p parent-hash)
      (block-validation-fail "State diff parent must be a hash32"))
    (let ((block-key (engine-payload-store-key block-hash)))
      (setf (gethash block-key (memory-chain-store-state-diffs store))
            (make-chain-state-diff
             :parent-key (engine-payload-store-key parent-hash)
             :balances (or balances (make-hash-table :test 'equal))
             :nonces (or nonces (make-hash-table :test 'equal))
             :codes (or codes (make-hash-table :test 'equal))
             :storage (or storage (make-hash-table :test 'equal)))
            (gethash block-key (memory-chain-store-state-blocks store))
            :diff))
    store))

;;; Full-view reconstruction.

(defun engine-payload-store-sorted-hash-keys (table)
  (let (keys)
    (maphash (lambda (key value)
               (declare (ignore value))
               (push key keys))
             table)
    (sort keys #'string<)))

(defun engine-payload-store-collect-prefixed-suffixes (table block-prefix view)
  (maphash
   (lambda (key value)
     (when (engine-payload-store-string-prefix-p block-prefix key)
       (setf (gethash (subseq key (length block-prefix)) view) value)))
   table))

(defun engine-payload-store-collect-state-view (store block-key)
  "Return the resolved full state at BLOCK-KEY as (VALUES BALANCES NONCES
CODES STORAGE) — plain suffix-keyed tables — or NIL when the diff chain does
not reach a baseline. Deleted accounts and zeroed slots are absent."
  (let ((diffs '())
        (remaining (engine-payload-store-state-walk-limit store)))
    ;; Walk newest to oldest; PUSH therefore leaves DIFFS oldest-first,
    ;; exactly the order they must apply over the baseline.
    (loop
      (when (minusp (decf remaining))
        (return-from engine-payload-store-collect-state-view nil))
      (case (engine-payload-store-state-kind-for-key store block-key)
        (:baseline (return))
        (:diff
         (let ((diff (engine-payload-store-state-diff-for-key
                      store block-key)))
           (unless diff
             (return-from engine-payload-store-collect-state-view nil))
           (push diff diffs)
           (setf block-key (chain-state-diff-parent-key diff))))
        (t (return-from engine-payload-store-collect-state-view nil))))
    ;; The baseline's block-prefixed entries seed the view.
    (let ((balances (make-hash-table :test 'equal))
          (nonces (make-hash-table :test 'equal))
          (codes (make-hash-table :test 'equal))
          (storage (make-hash-table :test 'equal))
          (block-prefix (format nil "~A:" block-key)))
      (engine-payload-store-collect-prefixed-suffixes
       (memory-chain-store-account-balances store) block-prefix balances)
      (engine-payload-store-collect-prefixed-suffixes
       (memory-chain-store-account-nonces store) block-prefix nonces)
      (engine-payload-store-collect-prefixed-suffixes
       (memory-chain-store-account-codes store) block-prefix codes)
      (engine-payload-store-collect-prefixed-suffixes
       (memory-chain-store-account-storage store) block-prefix storage)
      ;; A zero slot never denotes live state.
      (maphash (lambda (suffix value)
                 (when (and (integerp value) (zerop value))
                   (remhash suffix storage)))
               storage)
      ;; Apply the diffs oldest-first; :ABSENT and zero slots delete.
      (flet ((apply-diff-table (diff-table view &key storage-p)
               (maphash
                (lambda (suffix value)
                  (cond
                    ((eq value :absent)
                     (remhash suffix view))
                    ((and storage-p (integerp value) (zerop value))
                     (remhash suffix view))
                    (t
                     (setf (gethash suffix view) value))))
                diff-table)))
        (dolist (diff diffs)
          (apply-diff-table (chain-state-diff-balances diff) balances)
          (apply-diff-table (chain-state-diff-nonces diff) nonces)
          (apply-diff-table (chain-state-diff-codes diff) codes)
          (apply-diff-table (chain-state-diff-storage diff) storage
                            :storage-p t)))
      (values balances nonces codes storage))))

(defun engine-payload-store-state-view-addresses
    (balances nonces codes storage)
  "Return the sorted address hexes present in a collected state view."
  (let ((addresses (make-hash-table :test 'equal)))
    (flet ((remember-keys (view)
             (maphash (lambda (suffix value)
                        (declare (ignore value))
                        (setf (gethash suffix addresses) t))
                      view)))
      (remember-keys balances)
      (remember-keys nonces)
      (remember-keys codes))
    (maphash (lambda (suffix value)
               (declare (ignore value))
               (let ((separator (position #\: suffix)))
                 (when separator
                   (setf (gethash (subseq suffix 0 separator) addresses)
                         t))))
             storage)
    (engine-payload-store-sorted-hash-keys addresses)))

(defun engine-payload-store-state-view-storage-entries (storage address-hex)
  "Return ADDRESS-HEX's (slot-hash32 . value) entries from a view's storage
table, sorted by slot hex."
  (let ((account-prefix (format nil "~A:" address-hex))
        (entries '()))
    (maphash
     (lambda (suffix value)
       (when (engine-payload-store-string-prefix-p account-prefix suffix)
         (push (cons (subseq suffix (length account-prefix)) value)
               entries)))
     storage)
    (mapcar (lambda (entry)
              (cons (hash32-from-hex (car entry)) (cdr entry)))
            (sort entries #'string< :key #'car))))

;;; Promotion and pruning.

(defun engine-payload-store-promote-state-to-baseline (store block-key)
  "Materialize BLOCK-KEY's diff state as a full baseline so its ancestors
can be pruned. Returns T on success, NIL when the view is unresolvable."
  (multiple-value-bind (balances nonces codes storage)
      (engine-payload-store-collect-state-view store block-key)
    (unless balances
      (return-from engine-payload-store-promote-state-to-baseline nil))
    (flet ((publish (view table)
             (maphash (lambda (suffix value)
                        (setf (gethash (format nil "~A:~A" block-key suffix)
                                       table)
                              value))
                      view)))
      (publish balances (memory-chain-store-account-balances store))
      (publish nonces (memory-chain-store-account-nonces store))
      (publish codes (memory-chain-store-account-codes store))
      (publish storage (memory-chain-store-account-storage store)))
    (remhash block-key (memory-chain-store-state-diffs store))
    (setf (gethash block-key (memory-chain-store-state-blocks store))
          :baseline)
    t))

(defun engine-payload-store-remove-prefixed-keys (table prefix)
  (let ((keys '()))
    (maphash
     (lambda (key value)
       (declare (ignore value))
       (when (engine-payload-store-string-prefix-p prefix key)
         (push key keys)))
     table)
    (dolist (key keys)
      (remhash key table))
    (length keys)))

(defun engine-payload-store-prune-state-snapshot (store block-key)
  (setf store (chain-store-require-memory-store store))
  (let ((prefix (format nil "~A:" block-key)))
    (remhash block-key (memory-chain-store-state-blocks store))
    (remhash block-key (memory-chain-store-state-diffs store))
    (+ (engine-payload-store-remove-prefixed-keys
        (memory-chain-store-account-balances store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (memory-chain-store-account-nonces store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (memory-chain-store-account-codes store)
        prefix)
       (engine-payload-store-remove-prefixed-keys
        (memory-chain-store-account-storage store)
        prefix))))

(defun chain-store-prune-state-before (store block-number)
  (let ((store (chain-store-require-memory-store store)))
    (unless (and (integerp block-number) (not (minusp block-number)))
      (block-validation-fail
       "Chain state pruning block number must be a non-negative integer"))
    (let ((block-keys '())
          (kept-keys '())
          (head-block-key
            (let ((checkpoint
                    (memory-chain-store-head-checkpoint store)))
              (let ((hash (and checkpoint
                               (chain-store-checkpoint-block-hash
                                checkpoint))))
                (if hash
                    (engine-payload-store-key hash)
                    (gethash
                     (memory-chain-store-head-number store)
                     (memory-chain-store-canonical-hashes
                      store)))))))
      (maphash
       (lambda (block-key state-available-p)
         (when state-available-p
           (let ((block (gethash block-key
                                  (memory-chain-store-blocks store))))
             (if (and block
                      (or (null head-block-key)
                          (not (string= block-key head-block-key)))
                      (< (block-header-number (block-header block))
                         block-number))
                 (push block-key block-keys)
                 (push block-key kept-keys)))))
       (memory-chain-store-state-blocks store))
      ;; A kept diff whose parent is being dropped must become a baseline
      ;; first, or the drop would strand its whole descendant chain.
      (let ((dropped (make-hash-table :test 'equal)))
        (dolist (block-key block-keys)
          (setf (gethash block-key dropped) t))
        (dolist (block-key kept-keys)
          (when (eq :diff (engine-payload-store-state-kind-for-key
                           store block-key))
            (let ((diff (engine-payload-store-state-diff-for-key
                         store block-key)))
              (when (and diff
                         (let ((parent-key
                                 (chain-state-diff-parent-key diff)))
                           (or (gethash parent-key dropped)
                               (null
                                (engine-payload-store-state-kind-for-key
                                 store parent-key)))))
                (unless (engine-payload-store-promote-state-to-baseline
                         store block-key)
                  ;; Unresolvable already; drop it rather than keep a
                  ;; stranded diff.
                  (push block-key block-keys)
                  (setf (gethash block-key dropped) t)))))))
      (dolist (block-key block-keys)
        (engine-payload-store-prune-state-snapshot store block-key))
      (length block-keys))))
