(in-package #:ethereum-lisp.evm.internal)

(defstruct (evm-frame-snapshot
            (:constructor make-evm-frame-snapshot
                (&key transient-storage storage-clears accessed-storage
                      accessed-addresses selfdestructed-addresses)))
  transient-storage
  storage-clears
  accessed-storage
  accessed-addresses
  selfdestructed-addresses)

(defstruct (evm-execution-snapshot
            (:constructor make-evm-execution-snapshot
                (&key state transient-storage storage-clears accessed-storage
                      accessed-addresses selfdestructed-addresses)))
  state
  transient-storage
  storage-clears
  accessed-storage
  accessed-addresses
  selfdestructed-addresses)

(defstruct (evm-root-execution-snapshot
            (:constructor make-evm-root-execution-snapshot
                (&key execution frame storage-originals)))
  "Rollback data for an execution-tree host abort, not an EVM frame revert."
  execution
  frame
  storage-originals)

(defun copy-storage-originals (context)
  (let ((copy (make-hash-table :test 'equalp)))
    (when context
      (maphash (lambda (key value)
                 (setf (gethash key copy) value))
               (evm-context-storage-originals context)))
    copy))

(defun restore-storage-originals (context snapshot)
  (when context
    (let ((originals (evm-context-storage-originals context)))
      (clrhash originals)
      (maphash (lambda (key value)
                 (setf (gethash key originals) value))
               snapshot))))

(defun capture-frame-snapshot (context)
  (make-evm-frame-snapshot
   :transient-storage (copy-transient-storage context)
   :storage-clears (copy-storage-clears context)
   :accessed-storage (copy-accessed-storage context)
   :accessed-addresses (copy-accessed-addresses context)
   :selfdestructed-addresses (copy-selfdestructed-addresses context)))

(defun restore-frame-snapshot (context snapshot)
  (restore-transient-storage
   context
   (evm-frame-snapshot-transient-storage snapshot))
  (restore-storage-clears
   context
   (evm-frame-snapshot-storage-clears snapshot))
  (restore-accessed-storage
   context
   (evm-frame-snapshot-accessed-storage snapshot))
  (restore-accessed-addresses
   context
   (evm-frame-snapshot-accessed-addresses snapshot))
  (restore-selfdestructed-addresses
   context
   (evm-frame-snapshot-selfdestructed-addresses snapshot)))

(defun capture-execution-snapshot (state context)
  (make-evm-execution-snapshot
   :state (state-db-copy state)
   :transient-storage (copy-transient-storage context)
   :storage-clears (copy-storage-clears context)
   :accessed-storage (copy-accessed-storage context)
   :accessed-addresses (copy-accessed-addresses context)
   :selfdestructed-addresses (copy-selfdestructed-addresses context)))

(defun refresh-execution-snapshot-accessed-addresses (snapshot context)
  (setf (evm-execution-snapshot-accessed-addresses snapshot)
        (copy-accessed-addresses context))
  snapshot)

(defun restore-execution-snapshot (state context snapshot)
  (state-db-restore state (evm-execution-snapshot-state snapshot))
  (restore-transient-storage
   context
   (evm-execution-snapshot-transient-storage snapshot))
  (restore-storage-clears
   context
   (evm-execution-snapshot-storage-clears snapshot))
  (restore-accessed-storage
   context
   (evm-execution-snapshot-accessed-storage snapshot))
  (restore-accessed-addresses
   context
   (evm-execution-snapshot-accessed-addresses snapshot))
  (restore-selfdestructed-addresses
   context
   (evm-execution-snapshot-selfdestructed-addresses snapshot)))

(defun capture-root-execution-snapshot (state context)
  "Capture all mutable execution data for a non-protocol host abort."
  (make-evm-root-execution-snapshot
   :execution (and state (capture-execution-snapshot state context))
   :frame (and (null state) (capture-frame-snapshot context))
   :storage-originals (copy-storage-originals context)))

(defun restore-root-execution-snapshot (state context snapshot)
  (cond
    ((evm-root-execution-snapshot-execution snapshot)
     (restore-execution-snapshot
      state context (evm-root-execution-snapshot-execution snapshot)))
    ((evm-root-execution-snapshot-frame snapshot)
     (restore-frame-snapshot
      context (evm-root-execution-snapshot-frame snapshot))))
  (restore-storage-originals
   context
   (evm-root-execution-snapshot-storage-originals snapshot)))
