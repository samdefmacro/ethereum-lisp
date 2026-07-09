(in-package #:ethereum-lisp.evm)

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
