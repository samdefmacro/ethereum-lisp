(in-package #:ethereum-lisp.txpool.index)

(defconstant +txpool-replacement-price-bump-percent+ 10)

(defstruct (engine-pending-txpool
            (:constructor make-engine-pending-txpool
                (&key (transactions (make-hash-table :test 'equalp))
                      (transactions-by-sender
                       (make-hash-table :test 'equalp))
                      (queued-transactions
                       (make-hash-table :test 'equalp))
                      (queued-transactions-by-sender
                       (make-hash-table :test 'equalp))
                      (basefee-transactions
                       (make-hash-table :test 'equalp))
                      (basefee-transactions-by-sender
                       (make-hash-table :test 'equalp))
                      (blob-transactions
                       (make-hash-table :test 'equalp))
                      (blob-transactions-by-sender
                       (make-hash-table :test 'equalp))
                      (transaction-admitted-at
                       (make-hash-table :test 'equalp))
                      account-slot-limit
                      global-slot-limit
                      local-transaction-predicate
                      (database-change-tracking-enabled-p nil)
                      (database-dirty-transaction-keys
                       (make-hash-table :test 'equalp))
                      (change-sequence 0)
                      (change-log '()))))
  transactions
  transactions-by-sender
  queued-transactions
  queued-transactions-by-sender
  basefee-transactions
  basefee-transactions-by-sender
  blob-transactions
  blob-transactions-by-sender
  transaction-admitted-at
  account-slot-limit
  global-slot-limit
  local-transaction-predicate
  database-change-tracking-enabled-p
  database-dirty-transaction-keys
  (change-sequence 0 :type (integer 0 *))
  (change-log '() :type list))

(defvar *engine-pending-txpool-change-recorder* nil)

(defvar *engine-pending-txpool-undo-recorder* nil
  "Dynamically injected recorder called with TABLE and KEY before mutation.")

(defconstant +engine-pending-txpool-change-log-limit+ 8192)

(defun call-with-engine-pending-txpool-undo-recording (recorder thunk)
  "Call THUNK while RECORDER observes each mutable txpool table/key write.

The node-store transaction boundary supplies its changed-key journal here so
the txpool and chain store remain sibling domains instead of depending on one
another. Nested calls compose: both the inner and outer transaction frames
are preserved because the inner node-store frame records the write and merges
its before-image into the outer frame on success."
  (unless (and (functionp recorder) (functionp thunk))
    (block-validation-fail
     "Txpool undo recording requires recorder and thunk functions"))
  (let ((*engine-pending-txpool-undo-recorder* recorder))
    (funcall thunk)))

(defun engine-pending-txpool-journal-puthash (table key value)
  (when *engine-pending-txpool-undo-recorder*
    (funcall *engine-pending-txpool-undo-recorder* table key))
  (setf (gethash key table) value))

(defun engine-pending-txpool-journal-remhash (table key)
  (when *engine-pending-txpool-undo-recorder*
    (funcall *engine-pending-txpool-undo-recorder* table key))
  (remhash key table))

(defun engine-pending-txpool-configure-promotion-policy
    (txpool account-slot-limit global-slot-limit local-transaction-predicate)
  (setf (engine-pending-txpool-account-slot-limit txpool) account-slot-limit
        (engine-pending-txpool-global-slot-limit txpool) global-slot-limit
        (engine-pending-txpool-local-transaction-predicate txpool)
        local-transaction-predicate)
  txpool)

(defun engine-pending-txpool-record-transaction-change (txpool transaction)
  (let ((hash (transaction-hash transaction)))
    (let ((sequence
            (incf (engine-pending-txpool-change-sequence txpool))))
      (push (cons sequence hash)
            (engine-pending-txpool-change-log txpool))
      (when (> (length (engine-pending-txpool-change-log txpool))
               +engine-pending-txpool-change-log-limit+)
        (setf (engine-pending-txpool-change-log txpool)
              (subseq
               (engine-pending-txpool-change-log txpool)
               0 +engine-pending-txpool-change-log-limit+))))
    (when (engine-pending-txpool-database-change-tracking-enabled-p txpool)
      (engine-pending-txpool-journal-puthash
       (engine-pending-txpool-database-dirty-transaction-keys txpool)
       (hash32-to-hex hash)
       t))
    (when *engine-pending-txpool-change-recorder*
      (funcall *engine-pending-txpool-change-recorder* hash))))

(defun engine-pending-txpool-changes-since (txpool sequence)
  "Return hashes recorded after SEQUENCE, the current cursor, and overflow-p."
  (let* ((current (engine-pending-txpool-change-sequence txpool))
         (log (engine-pending-txpool-change-log txpool))
         (oldest (and log (car (car (last log)))))
         (overflow-p (and oldest (< sequence (1- oldest)))))
    (values
     (unless overflow-p
       (nreverse
        (loop for (entry-sequence . hash) in log
              when (> entry-sequence sequence)
                collect hash)))
     current
     overflow-p)))

(defun call-with-engine-pending-txpool-change-tracking (recorder thunk)
  (unless (and (functionp recorder) (functionp thunk))
    (block-validation-fail
     "Txpool change tracking requires recorder and thunk functions"))
  (let ((outer-recorder *engine-pending-txpool-change-recorder*))
    (let ((*engine-pending-txpool-change-recorder*
            (lambda (hash)
              (when outer-recorder
                (funcall outer-recorder hash))
              (funcall recorder hash))))
      (funcall thunk))))

(defun engine-pending-txpool-enable-database-change-tracking (txpool)
  (dolist (key
            (loop for key being the hash-keys of
                    (engine-pending-txpool-database-dirty-transaction-keys
                     txpool)
                  collect key))
    (engine-pending-txpool-journal-remhash
     (engine-pending-txpool-database-dirty-transaction-keys txpool) key))
  (setf (engine-pending-txpool-database-change-tracking-enabled-p txpool) t)
  txpool)

(defun engine-pending-txpool-database-dirty-transaction-hashes (txpool)
  (mapcar
   #'hash32-from-hex
   (sort
    (loop for key being the hash-keys of
            (engine-pending-txpool-database-dirty-transaction-keys txpool)
          collect key)
    #'string<)))

(defun engine-pending-txpool-clear-database-dirty-transaction-hashes
    (txpool &optional hashes)
  (if hashes
      (dolist (hash hashes)
        (engine-pending-txpool-journal-remhash
         (engine-pending-txpool-database-dirty-transaction-keys txpool)
         (hash32-to-hex hash)))
      (dolist (key
                (loop for key being the hash-keys of
                        (engine-pending-txpool-database-dirty-transaction-keys
                         txpool)
                      collect key))
        (engine-pending-txpool-journal-remhash
         (engine-pending-txpool-database-dirty-transaction-keys txpool) key)))
  txpool)

(defgeneric txpool-component (store)
  (:documentation "Return STORE's txpool component, or NIL when none exists."))

(defmethod txpool-component ((store t))
  nil)

(defmethod txpool-component ((txpool engine-pending-txpool))
  txpool)
