(in-package #:ethereum-lisp.node-store)

(defun node-store-require-memory-state (store)
  (unless (typep store 'engine-payload-memory-store)
    (block-validation-fail "Node store must be an engine payload memory store"))
  store)

(defun engine-payload-store-snapshot (store)
  (setf store (node-store-require-memory-state store))
  (make-engine-payload-memory-store
   :chain-store (copy-memory-chain-store store)
   :txpool
   (engine-pending-txpool-copy
    (engine-payload-memory-store-txpool store))))

(defun engine-payload-store-restore (store snapshot)
  (setf store (node-store-require-memory-state store)
        snapshot (node-store-require-memory-state snapshot))
  (setf (engine-payload-memory-store-chain-store store)
        (engine-payload-memory-store-chain-store snapshot)
        (engine-payload-memory-store-txpool store)
        (engine-payload-memory-store-txpool snapshot))
  store)

(defun chain-store-atomic-commit (store thunk)
  "Run THUNK, publishing its chain-store mutations only if it returns normally.

Rather than deep-copying the whole store up front, the growing tables record a
changed-key undo journal while the transaction is active, so a failed commit
rolls back in time proportional to the keys it touched. The small side slots
whose values are mutated in place (or that a journal cannot cheaply protect)
are captured as a bounded wholesale copy. Txpool tables join the same journal;
only their constant-size scalar/change-log heads are snapshotted."
  (let* ((store (node-store-require-memory-state store))
         (chain-store (chain-store-require-memory-store store))
         (txpool (engine-payload-memory-store-txpool store))
         (txpool-snapshot
           (engine-pending-txpool-transaction-snapshot txpool))
         (volatile-snapshot
           (chain-store-capture-volatile-slots chain-store))
         (journal nil)
         (completed-p nil))
    ;; Keep the completion boundary outside CALL-WITH-CHAIN-STORE-TRANSACTION:
    ;; its normal-return epilogue merges a nested savepoint into its parent, and
    ;; a failure there must roll back the child's already-published mutations as
    ;; surely as a failure in THUNK. The captured journal remains valid after
    ;; its dynamic binding unwinds, and rollback uses raw table operations.
    (unwind-protect
         (multiple-value-prog1
             (call-with-chain-store-transaction
              (lambda (transaction-journal)
                (setf journal transaction-journal)
                (call-with-engine-pending-txpool-undo-recording
                 (lambda (table key)
                   (chain-store-journal-record-key journal table key))
                 thunk)))
           ;; ERROR handlers do not run for THROW, RETURN-FROM, or other
           ;; non-local exits. Set this only after the journal merge returns;
           ;; MULTIPLE-VALUE-PROG1 preserves THUNK's normal values.
           (setf completed-p t))
      (unless completed-p
        (when journal
          (chain-store-journal-rollback journal))
        (chain-store-restore-volatile-slots
         chain-store volatile-snapshot)
        (engine-pending-txpool-restore-transaction-snapshot
         txpool txpool-snapshot)))))
