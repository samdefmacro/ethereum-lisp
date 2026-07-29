(in-package #:ethereum-lisp.execution)

(defun execution-storage-access-key (address slot)
  (concat-bytes (address-bytes address)
                (hash32-bytes slot)))

(defun execution-account-access-key (address)
  (address-bytes address))

(defun prewarm-execution-address (accessed-addresses address)
  (when address
    (setf (gethash (execution-account-access-key address)
                   accessed-addresses)
          t)))

(defun transaction-accessed-addresses-table
    (tx &key sender destination coinbase chain-rules)
  (let ((accessed-addresses (make-hash-table :test 'equalp)))
    (prewarm-precompile-addresses accessed-addresses chain-rules)
    (prewarm-execution-address accessed-addresses sender)
    (prewarm-execution-address accessed-addresses destination)
    (when (or (null chain-rules)
              (chain-rules-shanghai-p chain-rules))
      (prewarm-execution-address accessed-addresses coinbase))
    (dolist (entry (transaction-access-list tx))
      (prewarm-execution-address accessed-addresses
                                 (access-list-entry-address entry)))
    ;; EIP-7702: each recoverable authorization authority is warmed, even when
    ;; the tuple is later found invalid.
    (when (typep tx 'set-code-transaction)
      (dolist (authorization (transaction-authorization-list tx))
        (prewarm-execution-address
         accessed-addresses
         (set-code-authorization-authority authorization))))
    accessed-addresses))

(defun transaction-accessed-storage-table (tx)
  (let ((accessed-storage (make-hash-table :test 'equalp)))
    (dolist (entry (transaction-access-list tx))
      (dolist (slot (access-list-entry-storage-keys entry))
        (setf (gethash (execution-storage-access-key
                        (access-list-entry-address entry)
                        slot)
                       accessed-storage)
              t)))
    accessed-storage))

;;;; EIP-7928 block access-list construction.

(defstruct (block-access-phase
            (:constructor make-block-access-phase ()))
  (account-reads (make-hash-table :test 'equal))
  (storage-reads (make-hash-table :test 'equal))
  (initial-accounts (make-hash-table :test 'equal))
  (initial-storage (make-hash-table :test 'equal)))

(defstruct (construction-block-access-account
            (:constructor make-construction-block-access-account (address)))
  address
  (storage-writes (make-hash-table :test 'equal))
  (storage-reads (make-hash-table :test 'equal))
  (balance-changes (make-hash-table :test 'eql))
  (nonce-changes (make-hash-table :test 'eql))
  (code-changes (make-hash-table :test 'eql)))

(defstruct (construction-block-access-list
            (:constructor make-construction-block-access-list ()))
  (accounts (make-hash-table :test 'equal)))

(defun construction-address-key (address)
  (ethereum-lisp.hex:bytes-to-hex (address-bytes address) :prefix nil))

(defun construction-storage-key (address slot)
  (format nil "~A:~A"
          (construction-address-key address)
          (ethereum-lisp.hex:bytes-to-hex
           (hash32-bytes slot) :prefix nil)))

(defun copy-construction-state-account (account)
  (and account
       (make-state-account
        :nonce (state-account-nonce account)
        :balance (state-account-balance account)
        :storage-root (state-account-storage-root account)
        :code-hash (state-account-code-hash account))))

(defun block-access-phase-record
    (phase event state address slot)
  (let ((address-key (construction-address-key address)))
    (labels ((record-account-read ()
               (setf (gethash address-key
                              (block-access-phase-account-reads phase))
                     address))
             (capture-account-before-write ()
               (multiple-value-bind (value present-p)
                   (gethash address-key
                            (block-access-phase-initial-accounts phase))
                 (declare (ignore value))
                 (unless present-p
                   (let ((*state-access-recorder* nil))
                     (setf (gethash
                            address-key
                            (block-access-phase-initial-accounts phase))
                           (cons t
                                 (copy-construction-state-account
                                  (state-db-get-account state address)))))))))
      (ecase event
        (:account-read
         (record-account-read))
        (:account-write
         (record-account-read)
         (capture-account-before-write))
        (:storage-read
         (record-account-read)
         (setf (gethash (construction-storage-key address slot)
                        (block-access-phase-storage-reads phase))
               (cons address slot)))
        (:storage-write
         (record-account-read)
         (let ((key (construction-storage-key address slot)))
           (multiple-value-bind (value present-p)
               (gethash key (block-access-phase-initial-storage phase))
             (declare (ignore value))
             (unless present-p
               (let ((*state-access-recorder* nil))
                 (setf (gethash key
                                (block-access-phase-initial-storage phase))
                       (list address slot
                             (state-db-get-storage state address slot))))))))))))

(defun construction-account (construction address)
  (let ((key (construction-address-key address)))
    (or (gethash key (construction-block-access-list-accounts construction))
        (setf (gethash key
                       (construction-block-access-list-accounts construction))
              (make-construction-block-access-account address)))))

(defun state-account-balance-or-zero (account)
  (if account (state-account-balance account) 0))

(defun state-account-nonce-or-zero (account)
  (if account (state-account-nonce account) 0))

(defun state-account-code-hash-or-empty (account)
  (if account (state-account-code-hash account) +empty-code-hash+))

(defun merge-block-access-phase (construction phase state tx-index)
  (maphash
   (lambda (key address)
     (declare (ignore key))
     (construction-account construction address))
   (block-access-phase-account-reads phase))
  (maphash
   (lambda (key entry)
     (let* ((address (car entry))
            (slot (cdr entry))
            (account (construction-account construction address)))
       (unless (gethash key
                        (construction-block-access-account-storage-writes
                         account))
         (setf (gethash key
                        (construction-block-access-account-storage-reads
                         account))
               slot))))
   (block-access-phase-storage-reads phase))
  (maphash
   (lambda (key entry)
     (destructuring-bind (address slot initial-value) entry
       (let ((*state-access-recorder* nil))
         (let ((final-value (state-db-get-storage state address slot)))
           (unless (= initial-value final-value)
             (let* ((account (construction-account construction address))
                    (writes
                      (or (gethash
                           key
                           (construction-block-access-account-storage-writes
                            account))
                          (setf
                           (gethash
                            key
                            (construction-block-access-account-storage-writes
                             account))
                           (cons slot (make-hash-table :test 'eql))))))
               (setf (gethash tx-index (cdr writes)) final-value)
               (remhash key
                        (construction-block-access-account-storage-reads
                         account))))))))
   (block-access-phase-initial-storage phase))
  (maphash
   (lambda (key wrapped-initial)
     (let* ((initial (cdr wrapped-initial))
            (address
              (gethash key (block-access-phase-account-reads phase))))
       (when address
         (let ((*state-access-recorder* nil))
           (let* ((final (state-db-get-account state address))
                  (account (construction-account construction address)))
             (unless (= (state-account-balance-or-zero initial)
                        (state-account-balance-or-zero final))
               (setf
                (gethash
                 tx-index
                 (construction-block-access-account-balance-changes account))
                (state-account-balance-or-zero final)))
             (unless (= (state-account-nonce-or-zero initial)
                        (state-account-nonce-or-zero final))
               (setf
                (gethash
                 tx-index
                 (construction-block-access-account-nonce-changes account))
                (state-account-nonce-or-zero final)))
             (unless (hash32=
                      (state-account-code-hash-or-empty initial)
                      (state-account-code-hash-or-empty final))
               (setf
                (gethash
                 tx-index
                 (construction-block-access-account-code-changes account))
                (state-db-get-code state address))))))))
   (block-access-phase-initial-accounts phase))
  construction)

(defun call-with-block-access-phase (construction state tx-index thunk)
  (if (null construction)
      (funcall thunk)
      (let ((phase (make-block-access-phase)))
        (multiple-value-prog1
            (let ((*state-access-recorder*
                    (lambda (event event-state address slot)
                      (block-access-phase-record
                       phase event event-state address slot))))
              (funcall thunk))
          (merge-block-access-phase construction phase state tx-index)))))

(defun sorted-hash-table-values (table lessp key-function)
  (sort (loop for value being the hash-values of table collect value)
        lessp
        :key key-function))

(defun sorted-index-changes (table constructor)
  (loop for index in (sort (loop for key being the hash-keys of table
                                 collect key)
                           #'<)
        collect (funcall constructor index (gethash index table))))

(defun construction-block-access-list-value (construction)
  (loop for account
          in (sorted-hash-table-values
              (construction-block-access-list-accounts construction)
              #'byte-vector-lexicographic<
              (lambda (entry)
                (address-bytes
                 (construction-block-access-account-address entry))))
        collect
        (make-block-access-account
         :address (construction-block-access-account-address account)
         :storage-writes
         (loop for writes
                 in (sorted-hash-table-values
                     (construction-block-access-account-storage-writes account)
                     #'byte-vector-lexicographic<
                     (lambda (entry) (hash32-bytes (car entry))))
               collect
               (make-block-access-slot-writes
                :slot (car writes)
                :accesses
                (sorted-index-changes
                 (cdr writes)
                 (lambda (index value)
                   (make-block-access-storage-write
                    :tx-index index :value-after value)))))
         :storage-reads
         (sorted-hash-table-values
          (construction-block-access-account-storage-reads account)
          #'byte-vector-lexicographic<
          #'hash32-bytes)
         :balance-changes
         (sorted-index-changes
          (construction-block-access-account-balance-changes account)
          (lambda (index value)
            (make-block-access-balance-change
             :tx-index index :balance value)))
         :nonce-changes
         (sorted-index-changes
          (construction-block-access-account-nonce-changes account)
          (lambda (index value)
            (make-block-access-nonce-change
             :tx-index index :nonce value)))
         :code-changes
         (sorted-index-changes
          (construction-block-access-account-code-changes account)
          (lambda (index value)
            (make-block-access-code-change
             :tx-index index :code value))))))
