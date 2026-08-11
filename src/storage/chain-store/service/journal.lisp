(in-package #:ethereum-lisp.chain-store)

;;;; Changed-key undo journal for CHAIN-STORE-ATOMIC-COMMIT.
;;;;
;;;; A commit used to be made atomic by deep-copying the entire memory chain
;;;; store up front and swapping the copy back on failure -- O(total accumulated
;;;; state) on every block, even for a commit that changes a handful of keys.
;;;; Instead, while a transaction is active the growing tables record the FIRST
;;;; prior value for each key they touch, and a failed commit replays those undo
;;;; entries. Rollback work is then proportional to the keys the commit changed,
;;;; not to the size of the whole store.
;;;;
;;;; The node-store composition boundary injects this same first-touch recorder
;;;; into txpool table writes.  Txpool remains independent of chain-store while
;;;; its top-level and nested sender-index keys participate in the same savepoint
;;;; and rollback order.
;;;;
;;;; The journal only protects tables whose VALUES are immutable once stored:
;;;; blocks are copied on write and read out by copy, account values are
;;;; integers or freshly copied byte vectors, state diffs are immutable once
;;;; installed, transaction locations and sidecars are rebuilt on write. Slots
;;;; whose stored VALUES are mutated in place (the log-filter structs an
;;;; in-flight notification appends to, the invalid-block hit counters) or that
;;;; are small bounded side caches are instead captured as a cheap wholesale
;;;; copy by CHAIN-STORE-CAPTURE-VOLATILE-SLOTS. Those copies are bounded
;;;; independently of chain length, so per-commit work still does not scale with
;;;; total accumulated state.

(defvar *chain-store-transaction* nil
  "The active CHAIN-STORE-JOURNAL, or NIL. Bound only for the extent of one
CHAIN-STORE-ATOMIC-COMMIT thunk; the journaled helpers mutate directly when it
is NIL, so reads and non-transactional writes pay nothing.")

(defstruct (chain-store-journal
            (:constructor make-chain-store-journal (&key parent)))
  ;; Enclosing frame, or NIL for the outermost transaction. CHAIN-STORE-ATOMIC-
  ;; COMMIT nests (a new-payload commit wraps the import's own atomic commit),
  ;; so each level gets its own frame that rolls back independently on failure
  ;; but folds into its parent on success -- proper savepoint semantics.
  (parent nil)
  ;; Each entry (TABLE KEY PRESENT-P OLD-VALUE) restores one touched key.
  (hash-undos nil :type list)
  ;; Each entry (RESTORE . OLD-VALUE) restores one scalar or struct slot.
  (slot-undos nil :type list)
  ;; First-touch dedupe: mutated TABLE -> a set using TABLE's equality test.
  (seen-tables (make-hash-table :test 'eq) :type hash-table)
  ;; First-touch dedupe for slots, keyed by the slot's accessor symbol.
  (seen-slots (make-hash-table :test 'eq) :type hash-table))

(defun chain-store-journal-record-key (journal table key)
  "Record TABLE's pre-transaction value at KEY, once per key."
  (let ((seen (or (gethash table (chain-store-journal-seen-tables journal))
                  (setf (gethash table
                                 (chain-store-journal-seen-tables journal))
                        ;; Match TABLE's equality contract. In particular,
                        ;; byte-vector keys in EQUALP tables must deduplicate
                        ;; even when a later write supplies a fresh vector.
                        (make-hash-table :test (hash-table-test table))))))
    (unless (gethash key seen)
      (setf (gethash key seen) t)
      (multiple-value-bind (old present-p) (gethash key table)
        (push (list table key present-p old)
              (chain-store-journal-hash-undos journal))))))

(defun chain-store-journal-puthash (table key value)
  "Like (SETF (GETHASH KEY TABLE) VALUE), recording undo when a transaction is
active. Returns VALUE."
  (let ((journal *chain-store-transaction*))
    (when journal
      (chain-store-journal-record-key journal table key)))
  (setf (gethash key table) value))

(defun chain-store-journal-remhash (table key)
  "Like (REMHASH KEY TABLE), recording undo when a transaction is active."
  (let ((journal *chain-store-transaction*))
    (when journal
      (chain-store-journal-record-key journal table key)))
  (remhash key table))

(defun chain-store-journal-record-slot (key old-value restore)
  "Record a scalar or struct slot's pre-transaction OLD-VALUE once under KEY (an
accessor symbol); RESTORE is a one-argument function reinstalling a value."
  (let ((journal *chain-store-transaction*))
    (when journal
      (let ((seen (chain-store-journal-seen-slots journal)))
        (unless (gethash key seen)
          (setf (gethash key seen) t)
          (push (cons restore old-value)
                (chain-store-journal-slot-undos journal)))))))

(defmacro define-journaled-slot-setter (name accessor)
  "Define (NAME STORE VALUE): record ACCESSOR's prior value, then set it."
  `(defun ,name (store value)
     (let ((store (chain-store-require-memory-store store)))
       (chain-store-journal-record-slot
        ',accessor
        (,accessor store)
        (lambda (old) (setf (,accessor store) old)))
       (setf (,accessor store) value))))

;; Only HEAD-NUMBER is journaled: its value is an immutable integer, so
;; recording the prior value and restoring it is exact. The forkchoice
;; checkpoints are struct objects a caller may mutate in place, so they are
;; captured by value in the volatile snapshot below instead.
(define-journaled-slot-setter chain-store-journaled-set-head-number
    memory-chain-store-head-number)

(defun chain-store-journal-undo-count (journal)
  "Distinct keys plus slots recorded -- the per-commit rollback work, which the
proportionality test asserts tracks the keys a commit touches rather than the
total store size."
  (+ (length (chain-store-journal-hash-undos journal))
     (length (chain-store-journal-slot-undos journal))))

(defun chain-store-journal-rollback (journal)
  "Undo every recorded mutation with raw operations, restoring the store to its
pre-transaction contents. Raw GETHASH/REMHASH are used so no undo is recorded
while unwinding, even though the transaction var may still be bound."
  (dolist (undo (chain-store-journal-hash-undos journal))
    (destructuring-bind (table key present-p old) undo
      (if present-p
          (setf (gethash key table) old)
          (remhash key table))))
  (dolist (undo (chain-store-journal-slot-undos journal))
    (funcall (car undo) (cdr undo)))
  journal)

(defun chain-store-journal-merge-into-parent (journal)
  "Fold a successfully completed frame's undos into its parent so the parent can
still roll them back. Child undos are newer, so prepending them makes a later
parent rollback replay them before the parent's own entries and thus restore
the parent-entry value last. The child's first-touch sets fold in too, so a
subsequent parent write to the same key does not record over the child's undo."
  (let ((parent (chain-store-journal-parent journal)))
    (when parent
      (setf (chain-store-journal-hash-undos parent)
            (append (chain-store-journal-hash-undos journal)
                    (chain-store-journal-hash-undos parent))
            (chain-store-journal-slot-undos parent)
            (append (chain-store-journal-slot-undos journal)
                    (chain-store-journal-slot-undos parent)))
      (maphash
       (lambda (table child-seen)
         (let ((parent-seen
                 (or (gethash table (chain-store-journal-seen-tables parent))
                     (setf (gethash table
                                    (chain-store-journal-seen-tables parent))
                           (make-hash-table
                            :test (hash-table-test child-seen))))))
           (maphash (lambda (key value)
                      (declare (ignore value))
                      (setf (gethash key parent-seen) t))
                    child-seen)))
       (chain-store-journal-seen-tables journal))
      (maphash (lambda (slot value)
                 (declare (ignore value))
                 (setf (gethash slot (chain-store-journal-seen-slots parent)) t))
               (chain-store-journal-seen-slots journal)))))

(defun call-with-chain-store-transaction (function)
  "Call FUNCTION with a fresh journal frame bound as the active transaction and
passed as its sole argument, so the caller can roll it back on failure. On
FUNCTION returning normally the frame folds into any enclosing frame; a
non-local exit (the caller's rollback re-signalling) skips the fold, so a
failed nested commit stays rolled back without disturbing its parent."
  (let* ((parent *chain-store-transaction*)
         (journal (make-chain-store-journal :parent parent)))
    (let ((*chain-store-transaction* journal))
      (multiple-value-prog1
          (funcall function journal)
        (chain-store-journal-merge-into-parent journal)))))

;;; Volatile side slots: values mutated in place (log filters, and the
;;; forkchoice checkpoint structs a caller may edit in place), or small bounded
;;; caches with in-place counters (invalid tipsets/hits) or immutable entries
;;; (forkchoice sync targets). A changed-key journal cannot cheaply protect
;;; in-place value mutation, so these are captured as a wholesale copy and
;;; restored on rollback. Each is bounded independently of chain length.

(defstruct (chain-store-volatile-snapshot
            (:constructor %make-chain-store-volatile-snapshot))
  remote-block-metadata
  forkchoice-sync-targets
  forkchoice-sync-target-metadata
  invalid-tipsets
  invalid-tipset-metadata
  invalid-block-hits
  prepared-payload-metadata
  blob-sidecar-metadata
  log-filters
  next-log-filter-id
  head-checkpoint
  safe-checkpoint
  finalized-checkpoint)

(defun chain-store-capture-volatile-slots (store)
  "Return a wholesale copy of the store's volatile side slots for rollback."
  (let ((store (chain-store-require-memory-store store)))
    (%make-chain-store-volatile-snapshot
     :remote-block-metadata
     (engine-payload-store-copy-cache-metadata-table
      (memory-chain-store-remote-block-metadata store))
     :forkchoice-sync-targets
     (engine-payload-store-copy-table
      (memory-chain-store-forkchoice-sync-targets store))
     :forkchoice-sync-target-metadata
     (engine-payload-store-copy-cache-metadata-table
      (memory-chain-store-forkchoice-sync-target-metadata store))
     :invalid-tipsets
     (engine-payload-store-copy-block-table
      (memory-chain-store-invalid-tipsets store))
     :invalid-tipset-metadata
     (engine-payload-store-copy-cache-metadata-table
      (memory-chain-store-invalid-tipset-metadata store))
     :invalid-block-hits
     (engine-payload-store-copy-table
      (memory-chain-store-invalid-block-hits store))
     :prepared-payload-metadata
     (engine-payload-store-copy-cache-metadata-table
      (memory-chain-store-prepared-payload-metadata store))
     :blob-sidecar-metadata
     (engine-payload-store-copy-cache-metadata-table
      (memory-chain-store-blob-sidecar-metadata store))
     :log-filters
     (engine-payload-store-copy-filter-table
      (memory-chain-store-log-filters store))
     :next-log-filter-id
     (memory-chain-store-next-log-filter-id store)
     :head-checkpoint
     (engine-payload-store-copy-checkpoint
      (memory-chain-store-head-checkpoint store))
     :safe-checkpoint
     (engine-payload-store-copy-checkpoint
      (memory-chain-store-safe-checkpoint store))
     :finalized-checkpoint
     (engine-payload-store-copy-checkpoint
      (memory-chain-store-finalized-checkpoint store)))))

(defun chain-store-restore-volatile-slots (store snapshot)
  "Reinstall the volatile side slots captured by
CHAIN-STORE-CAPTURE-VOLATILE-SLOTS."
  (let ((store (chain-store-require-memory-store store)))
    (setf (memory-chain-store-remote-block-metadata store)
          (chain-store-volatile-snapshot-remote-block-metadata snapshot)
          (memory-chain-store-forkchoice-sync-targets store)
          (chain-store-volatile-snapshot-forkchoice-sync-targets snapshot)
          (memory-chain-store-forkchoice-sync-target-metadata store)
          (chain-store-volatile-snapshot-forkchoice-sync-target-metadata
           snapshot)
          (memory-chain-store-invalid-tipsets store)
          (chain-store-volatile-snapshot-invalid-tipsets snapshot)
          (memory-chain-store-invalid-tipset-metadata store)
          (chain-store-volatile-snapshot-invalid-tipset-metadata snapshot)
          (memory-chain-store-invalid-block-hits store)
          (chain-store-volatile-snapshot-invalid-block-hits snapshot)
          (memory-chain-store-prepared-payload-metadata store)
          (chain-store-volatile-snapshot-prepared-payload-metadata snapshot)
          (memory-chain-store-blob-sidecar-metadata store)
          (chain-store-volatile-snapshot-blob-sidecar-metadata snapshot)
          (memory-chain-store-log-filters store)
          (chain-store-volatile-snapshot-log-filters snapshot)
          (memory-chain-store-next-log-filter-id store)
          (chain-store-volatile-snapshot-next-log-filter-id snapshot)
          (memory-chain-store-head-checkpoint store)
          (chain-store-volatile-snapshot-head-checkpoint snapshot)
          (memory-chain-store-safe-checkpoint store)
          (chain-store-volatile-snapshot-safe-checkpoint snapshot)
          (memory-chain-store-finalized-checkpoint store)
          (chain-store-volatile-snapshot-finalized-checkpoint snapshot))
    store))
